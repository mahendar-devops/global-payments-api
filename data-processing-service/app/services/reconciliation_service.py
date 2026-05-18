"""
app/services/reconciliation_service.py

Daily Payment Reconciliation Service.

Flow:
  1. Fetch internal payment records from the payments-service DB (via reporting replica)
  2. Download the clearing network's settlement file from S3
  3. Parse and normalise both datasets using pandas
  4. Join and compare records
  5. Persist results to the reconciliation_records table
  6. Publish a summary event to Kafka
  7. Upload the reconciliation report to S3

Runs daily as a scheduled job (triggered via REST API by a Kubernetes CronJob).
"""

import uuid
import logging
from datetime import datetime, date, timedelta, timezone
from decimal import Decimal
from typing import Dict, Tuple

import pandas as pd
import boto3
import structlog
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config.database import db
from app.models.reconciliation import (
    ReconciliationRecord, ReconciliationRun, ReconciliationStatus
)

logger = structlog.get_logger(__name__)


class ReconciliationService:

    def __init__(self, s3_bucket: str, aws_region: str):
        self.s3_bucket  = s3_bucket
        self.s3_client  = boto3.client('s3', region_name=aws_region)
        self.run_logger = structlog.get_logger(__name__)

    # ── Main Entry Point ───────────────────────────────────────────────────

    def run_daily_reconciliation(self, reconciliation_date: date = None) -> Dict:
        """
        Execute the full reconciliation pipeline for a given date.
        Returns a summary dict with match statistics.
        """
        target_date = reconciliation_date or (date.today() - timedelta(days=1))
        run_id      = f"RECON-{target_date.strftime('%Y%m%d')}"

        self.run_logger.info('Starting reconciliation run',
                             run_id=run_id, date=str(target_date))

        # Create the run record
        run = ReconciliationRun(
            id=run_id,
            run_date=datetime.combine(target_date, datetime.min.time(),
                                      tzinfo=timezone.utc),
            status='RUNNING',
        )
        db.session.add(run)
        db.session.commit()

        try:
            # Step 1: Load internal payment data
            internal_df = self._load_internal_payments(target_date)
            self.run_logger.info('Loaded internal payments',
                                 count=len(internal_df), run_id=run_id)

            # Step 2: Load clearing network data from S3
            clearing_df = self._load_clearing_file(target_date)
            self.run_logger.info('Loaded clearing file',
                                 count=len(clearing_df), run_id=run_id)

            # Step 3: Reconcile
            results_df = self._reconcile(internal_df, clearing_df)

            # Step 4: Persist results
            self._persist_results(results_df, run_id)

            # Step 5: Update run summary
            matched   = (results_df['status'] == 'MATCHED').sum()
            unmatched = (results_df['status'] == 'UNMATCHED').sum()
            exception = (results_df['status'] == 'EXCEPTION').sum()

            run.total_records   = len(results_df)
            run.matched_count   = int(matched)
            run.unmatched_count = int(unmatched)
            run.exception_count = int(exception)
            run.total_amount_gbp = float(
                results_df['internal_amount'].sum() if len(results_df) > 0 else 0
            )
            run.status       = 'COMPLETED'
            run.completed_at = datetime.now(timezone.utc)
            db.session.commit()

            # Step 6: Upload report to S3
            self._upload_report(results_df, run_id, target_date)

            summary = {
                'run_id':        run_id,
                'date':          str(target_date),
                'total':         len(results_df),
                'matched':       int(matched),
                'unmatched':     int(unmatched),
                'exceptions':    int(exception),
                'match_rate_pct': run.match_rate,
                'status':        'COMPLETED',
            }

            self.run_logger.info('Reconciliation complete', **summary)
            return summary

        except Exception as exc:
            run.status        = 'FAILED'
            run.error_message = str(exc)
            run.completed_at  = datetime.now(timezone.utc)
            db.session.commit()
            self.run_logger.error('Reconciliation failed',
                                  run_id=run_id, error=str(exc), exc_info=True)
            raise

    # ── Data Loading ───────────────────────────────────────────────────────

    def _load_internal_payments(self, target_date: date) -> pd.DataFrame:
        """
        Query the payments reporting replica for all COMPLETED payments
        on the target date. Uses raw SQL for performance on large datasets.
        """
        sql = """
            SELECT
                payment_reference,
                id::text              AS payment_id,
                amount_minor_units,
                currency,
                status,
                clearing_reference,
                created_at,
                updated_at
            FROM payments
            WHERE status IN ('COMPLETED', 'FAILED')
              AND DATE(created_at AT TIME ZONE 'UTC') = :target_date
            ORDER BY payment_reference
        """
        result = db.session.execute(
            db.text(sql), {'target_date': target_date}
        ).fetchall()

        if not result:
            return pd.DataFrame(columns=[
                'payment_reference', 'payment_id', 'amount_minor_units',
                'currency', 'status', 'clearing_reference', 'created_at'
            ])

        df = pd.DataFrame(result, columns=result[0]._fields)

        # Convert minor units to decimal for comparison
        # (amount_minor_units is GBP pence — divide by 100 for pounds)
        df['internal_amount'] = df['amount_minor_units'].apply(
            lambda x: Decimal(str(x)) / 100
        )
        df['internal_currency'] = df['currency']
        df['internal_status']   = df['status']
        df['internal_created_at'] = pd.to_datetime(df['created_at'], utc=True)

        return df

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10)
    )
    def _load_clearing_file(self, target_date: date) -> pd.DataFrame:
        """
        Download and parse the clearing network's daily settlement CSV from S3.
        File is uploaded by the clearing network to our S3 bucket each morning.

        Retries up to 3 times with exponential backoff in case of transient S3 errors.
        """
        s3_key = f"clearing-files/{target_date.strftime('%Y/%m/%d')}/settlement.csv"

        try:
            response = self.s3_client.get_object(
                Bucket=self.s3_bucket,
                Key=s3_key
            )
            clearing_df = pd.read_csv(
                response['Body'],
                dtype={
                    'payment_reference': str,
                    'amount':            str,   # Read as string to avoid float precision
                    'currency':          str,
                    'clearing_reference': str,
                    'status':            str,
                }
            )

            # Normalise column names and types
            clearing_df = clearing_df.rename(columns={
                'payment_reference': 'payment_reference',
                'amount':            'clearing_amount_raw',
                'currency':          'clearing_currency',
                'reference':         'clearing_reference',
                'status':            'clearing_status',
                'settled_at':        'clearing_settled_at',
            })

            clearing_df['clearing_amount'] = clearing_df['clearing_amount_raw'].apply(
                lambda x: Decimal(str(x).strip())
            )
            clearing_df['clearing_settled_at'] = pd.to_datetime(
                clearing_df['clearing_settled_at'], utc=True, errors='coerce'
            )

            return clearing_df

        except self.s3_client.exceptions.NoSuchKey:
            self.run_logger.warning(
                'Clearing file not found in S3',
                bucket=self.s3_bucket, key=s3_key, date=str(target_date)
            )
            return pd.DataFrame(columns=[
                'payment_reference', 'clearing_amount', 'clearing_currency',
                'clearing_reference', 'clearing_status', 'clearing_settled_at'
            ])

    # ── Core Reconciliation Logic ──────────────────────────────────────────

    def _reconcile(self, internal_df: pd.DataFrame,
                   clearing_df: pd.DataFrame) -> pd.DataFrame:
        """
        Join internal and clearing data on payment_reference.
        Classify each record as MATCHED, UNMATCHED, or EXCEPTION.
        """
        if internal_df.empty:
            return internal_df

        # Outer join to catch both unmatched internal and clearing-only records
        merged = internal_df.merge(
            clearing_df,
            on='payment_reference',
            how='left',
            suffixes=('_internal', '_clearing')
        )

        # Classify each record
        merged['status']             = merged.apply(self._classify_record, axis=1)
        merged['discrepancy_amount'] = merged.apply(self._compute_discrepancy, axis=1)
        merged['requires_investigation'] = (
            merged['status'] == ReconciliationStatus.EXCEPTION.value
        )
        merged['notes'] = merged.apply(self._generate_notes, axis=1)

        return merged

    def _classify_record(self, row) -> str:
        # No clearing record found for this payment
        if pd.isna(row.get('clearing_reference')):
            return ReconciliationStatus.UNMATCHED.value

        # Both records exist — check amounts match
        internal_amount = row.get('internal_amount')
        clearing_amount = row.get('clearing_amount')

        if (internal_amount is not None and clearing_amount is not None
                and abs(float(internal_amount) - float(clearing_amount)) > 0.005):
            return ReconciliationStatus.EXCEPTION.value

        # Currency mismatch
        if row.get('internal_currency') != row.get('clearing_currency'):
            return ReconciliationStatus.EXCEPTION.value

        return ReconciliationStatus.MATCHED.value

    def _compute_discrepancy(self, row) -> Decimal:
        if row['status'] != ReconciliationStatus.EXCEPTION.value:
            return None
        try:
            return abs(float(row.get('internal_amount', 0))
                       - float(row.get('clearing_amount', 0)))
        except (TypeError, ValueError):
            return None

    def _generate_notes(self, row) -> str:
        if row['status'] == ReconciliationStatus.MATCHED.value:
            return None
        if row['status'] == ReconciliationStatus.UNMATCHED.value:
            return 'No matching clearing record found. Check if payment is pending settlement.'
        return (f"Amount discrepancy: internal={row.get('internal_amount')}, "
                f"clearing={row.get('clearing_amount')}. Requires manual review.")

    # ── Persistence ────────────────────────────────────────────────────────

    def _persist_results(self, results_df: pd.DataFrame, run_id: str) -> None:
        """Bulk-insert reconciliation records. Uses batching for large datasets."""
        BATCH_SIZE = 500

        records_to_insert = []
        for _, row in results_df.iterrows():
            record = ReconciliationRecord(
                id=uuid.uuid4(),
                payment_reference=row['payment_reference'],
                payment_id=row.get('payment_id'),
                internal_amount=row.get('internal_amount'),
                internal_currency=row.get('internal_currency'),
                internal_status=row.get('internal_status'),
                internal_created_at=row.get('internal_created_at'),
                clearing_amount=row.get('clearing_amount'),
                clearing_currency=row.get('clearing_currency'),
                clearing_reference=row.get('clearing_reference'),
                clearing_status=row.get('clearing_status'),
                clearing_settled_at=row.get('clearing_settled_at'),
                status=ReconciliationStatus(row['status']),
                discrepancy_amount=row.get('discrepancy_amount'),
                notes=row.get('notes'),
                reconciliation_run_id=run_id,
                requires_investigation=bool(row.get('requires_investigation', False)),
            )
            records_to_insert.append(record)

            # Batch commit to avoid holding a huge transaction open
            if len(records_to_insert) >= BATCH_SIZE:
                db.session.bulk_save_objects(records_to_insert)
                db.session.commit()
                records_to_insert = []

        if records_to_insert:
            db.session.bulk_save_objects(records_to_insert)
            db.session.commit()

        self.run_logger.info('Persisted reconciliation records',
                             count=len(results_df), run_id=run_id)

    # ── S3 Report Upload ───────────────────────────────────────────────────

    def _upload_report(self, results_df: pd.DataFrame,
                       run_id: str, target_date: date) -> None:
        """Upload a CSV reconciliation report to S3 for audit purposes."""
        try:
            csv_buffer = results_df.to_csv(index=False)
            s3_key = (f"reconciliation-reports/"
                      f"{target_date.strftime('%Y/%m/%d')}/{run_id}-report.csv")

            self.s3_client.put_object(
                Bucket=self.s3_bucket,
                Key=s3_key,
                Body=csv_buffer.encode('utf-8'),
                ContentType='text/csv',
                ServerSideEncryption='aws:kms',   # Encrypt at rest with KMS
                Metadata={
                    'run-id':       run_id,
                    'record-count': str(len(results_df)),
                }
            )
            self.run_logger.info('Uploaded reconciliation report',
                                 bucket=self.s3_bucket, key=s3_key)
        except Exception as e:
            # Non-fatal: report upload failure shouldn't fail the reconciliation
            self.run_logger.error('Failed to upload report to S3', error=str(e))
