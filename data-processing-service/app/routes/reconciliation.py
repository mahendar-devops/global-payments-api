"""
app/routes/reconciliation.py
REST endpoints to trigger and inspect reconciliation runs.
Called by a Kubernetes CronJob at 06:00 UTC daily.
"""

from datetime import date, datetime
from flask import Blueprint, jsonify, request, current_app

from app.config.database import db
from app.models.reconciliation import ReconciliationRun, ReconciliationRecord
from app.services.reconciliation_service import ReconciliationService

reconciliation_bp = Blueprint('reconciliation', __name__)


def _get_service() -> ReconciliationService:
    return ReconciliationService(
        s3_bucket=current_app.config['S3_REPORTS_BUCKET'],
        aws_region=current_app.config['AWS_REGION'],
    )


# ── POST /api/v1/reconciliation/run ─────────────────────────────────────────
# Trigger a reconciliation run. Called by Kubernetes CronJob (internal only).

@reconciliation_bp.route('/run', methods=['POST'])
def trigger_reconciliation():
    body          = request.get_json(silent=True) or {}
    date_str      = body.get('date')
    target_date   = None

    if date_str:
        try:
            target_date = date.fromisoformat(date_str)
        except ValueError:
            return jsonify(
                code='VALIDATION_ERROR',
                message='Invalid date format. Use ISO 8601 (YYYY-MM-DD).'
            ), 400

    try:
        summary = _get_service().run_daily_reconciliation(target_date)
        return jsonify(summary), 200
    except Exception as exc:
        current_app.logger.error('Reconciliation trigger failed: %s', str(exc))
        return jsonify(code='RECONCILIATION_FAILED', message=str(exc)), 500


# ── GET /api/v1/reconciliation/runs ─────────────────────────────────────────

@reconciliation_bp.route('/runs', methods=['GET'])
def list_runs():
    limit  = min(int(request.args.get('limit', 30)), 90)
    offset = int(request.args.get('offset', 0))

    runs = (
        ReconciliationRun.query
        .order_by(ReconciliationRun.run_date.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )

    return jsonify([{
        'id':             r.id,
        'run_date':       r.run_date.isoformat() if r.run_date else None,
        'status':         r.status,
        'total_records':  r.total_records,
        'matched':        r.matched_count,
        'unmatched':      r.unmatched_count,
        'exceptions':     r.exception_count,
        'match_rate_pct': r.match_rate,
        'started_at':     r.started_at.isoformat() if r.started_at else None,
        'completed_at':   r.completed_at.isoformat() if r.completed_at else None,
    } for r in runs])


# ── GET /api/v1/reconciliation/runs/<run_id> ─────────────────────────────────

@reconciliation_bp.route('/runs/<run_id>', methods=['GET'])
def get_run(run_id):
    run = ReconciliationRun.query.get_or_404(run_id)
    return jsonify({
        'id':             run.id,
        'run_date':       run.run_date.isoformat() if run.run_date else None,
        'status':         run.status,
        'total_records':  run.total_records,
        'matched':        run.matched_count,
        'unmatched':      run.unmatched_count,
        'exceptions':     run.exception_count,
        'match_rate_pct': run.match_rate,
        'total_amount_gbp': str(run.total_amount_gbp),
        'error_message':  run.error_message,
        'started_at':     run.started_at.isoformat() if run.started_at else None,
        'completed_at':   run.completed_at.isoformat() if run.completed_at else None,
    })


# ── GET /api/v1/reconciliation/runs/<run_id>/records ─────────────────────────

@reconciliation_bp.route('/runs/<run_id>/records', methods=['GET'])
def get_run_records(run_id):
    status    = request.args.get('status')          # Optional filter: MATCHED|UNMATCHED|EXCEPTION
    page      = int(request.args.get('page', 1))
    per_page  = min(int(request.args.get('per_page', 50)), 200)
    only_exceptions = request.args.get('exceptions_only', 'false').lower() == 'true'

    query = ReconciliationRecord.query.filter_by(reconciliation_run_id=run_id)

    if status:
        query = query.filter_by(status=status)
    if only_exceptions:
        query = query.filter_by(requires_investigation=True)

    paginated = query.order_by(
        ReconciliationRecord.payment_reference
    ).paginate(page=page, per_page=per_page, error_out=False)

    return jsonify({
        'records':       [_serialize_record(r) for r in paginated.items],
        'page':          paginated.page,
        'per_page':      paginated.per_page,
        'total':         paginated.total,
        'total_pages':   paginated.pages,
    })


def _serialize_record(r: ReconciliationRecord) -> dict:
    return {
        'id':                    str(r.id),
        'payment_reference':     r.payment_reference,
        'internal_amount':       str(r.internal_amount),
        'internal_currency':     r.internal_currency,
        'internal_status':       r.internal_status,
        'clearing_amount':       str(r.clearing_amount) if r.clearing_amount else None,
        'clearing_reference':    r.clearing_reference,
        'clearing_status':       r.clearing_status,
        'status':                r.status.value if r.status else None,
        'discrepancy_amount':    str(r.discrepancy_amount) if r.discrepancy_amount else None,
        'requires_investigation':r.requires_investigation,
        'notes':                 r.notes,
        'reconciled_at':         r.reconciled_at.isoformat() if r.reconciled_at else None,
    }
