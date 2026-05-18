"""
tests/test_reconciliation_service.py
Unit tests for the ReconciliationService using mocked AWS and DB calls.
"""

import pytest
import pandas as pd
from decimal import Decimal
from datetime import date
from unittest.mock import MagicMock, patch, call

from app import create_app
from app.config.database import db
from app.services.reconciliation_service import ReconciliationService
from app.models.reconciliation import ReconciliationStatus


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope='session')
def app():
    """Create a test Flask app with in-memory SQLite."""
    application = create_app('testing')
    with application.app_context():
        db.create_all()
        yield application
        db.drop_all()


@pytest.fixture(autouse=True)
def clean_db(app):
    """Rollback DB after each test to ensure isolation."""
    with app.app_context():
        yield
        db.session.rollback()


@pytest.fixture
def service(app):
    """ReconciliationService with mocked S3."""
    with app.app_context():
        svc = ReconciliationService(
            s3_bucket='test-bucket',
            aws_region='eu-west-2',
        )
        svc.s3_client = MagicMock()
        yield svc


@pytest.fixture
def sample_internal_df():
    """Sample internal payments DataFrame."""
    return pd.DataFrame([
        {
            'payment_reference': 'PAY-20240315-000001-AB12',
            'payment_id':        'aaa-111',
            'amount_minor_units': 10000,
            'currency':          'GBP',
            'status':            'COMPLETED',
            'clearing_reference': 'CLR-001',
            'created_at':        '2024-03-15T10:00:00Z',
            'internal_amount':   Decimal('100.00'),
            'internal_currency': 'GBP',
            'internal_status':   'COMPLETED',
            'internal_created_at': pd.Timestamp('2024-03-15T10:00:00Z'),
        },
        {
            'payment_reference': 'PAY-20240315-000002-CD34',
            'payment_id':        'bbb-222',
            'amount_minor_units': 25050,
            'currency':          'GBP',
            'status':            'COMPLETED',
            'clearing_reference': 'CLR-002',
            'created_at':        '2024-03-15T11:00:00Z',
            'internal_amount':   Decimal('250.50'),
            'internal_currency': 'GBP',
            'internal_status':   'COMPLETED',
            'internal_created_at': pd.Timestamp('2024-03-15T11:00:00Z'),
        },
        {
            'payment_reference': 'PAY-20240315-000003-EF56',
            'payment_id':        'ccc-333',
            'amount_minor_units': 5000,
            'currency':          'GBP',
            'status':            'COMPLETED',
            'clearing_reference': None,
            'created_at':        '2024-03-15T12:00:00Z',
            'internal_amount':   Decimal('50.00'),
            'internal_currency': 'GBP',
            'internal_status':   'COMPLETED',
            'internal_created_at': pd.Timestamp('2024-03-15T12:00:00Z'),
        },
    ])


@pytest.fixture
def sample_clearing_df():
    """Sample clearing network DataFrame — matches first two records, misses third."""
    return pd.DataFrame([
        {
            'payment_reference': 'PAY-20240315-000001-AB12',
            'clearing_amount':   Decimal('100.00'),
            'clearing_currency': 'GBP',
            'clearing_reference': 'CLR-NET-001',
            'clearing_status':   'SETTLED',
            'clearing_settled_at': pd.Timestamp('2024-03-15T23:00:00Z'),
        },
        {
            'payment_reference': 'PAY-20240315-000002-CD34',
            'clearing_amount':   Decimal('999.99'),  # ← Amount mismatch
            'clearing_currency': 'GBP',
            'clearing_reference': 'CLR-NET-002',
            'clearing_status':   'SETTLED',
            'clearing_settled_at': pd.Timestamp('2024-03-15T23:01:00Z'),
        },
    ])


# ── Unit Tests: _classify_record ─────────────────────────────────────────────

class TestClassifyRecord:

    def test_matched_record_when_amounts_match(self, service):
        row = pd.Series({
            'clearing_reference': 'CLR-001',
            'internal_amount':    Decimal('100.00'),
            'clearing_amount':    Decimal('100.00'),
            'internal_currency':  'GBP',
            'clearing_currency':  'GBP',
        })
        assert service._classify_record(row) == ReconciliationStatus.MATCHED.value

    def test_unmatched_record_when_no_clearing_reference(self, service):
        row = pd.Series({
            'clearing_reference': None,
            'internal_amount':    Decimal('50.00'),
            'clearing_amount':    None,
            'internal_currency':  'GBP',
            'clearing_currency':  None,
        })
        assert service._classify_record(row) == ReconciliationStatus.UNMATCHED.value

    def test_exception_when_amount_mismatch(self, service):
        row = pd.Series({
            'clearing_reference': 'CLR-002',
            'internal_amount':    Decimal('250.50'),
            'clearing_amount':    Decimal('999.99'),
            'internal_currency':  'GBP',
            'clearing_currency':  'GBP',
        })
        assert service._classify_record(row) == ReconciliationStatus.EXCEPTION.value

    def test_exception_when_currency_mismatch(self, service):
        row = pd.Series({
            'clearing_reference': 'CLR-003',
            'internal_amount':    Decimal('100.00'),
            'clearing_amount':    Decimal('100.00'),
            'internal_currency':  'GBP',
            'clearing_currency':  'USD',   # ← Mismatch
        })
        assert service._classify_record(row) == ReconciliationStatus.EXCEPTION.value

    def test_matched_within_tolerance(self, service):
        """Small floating point differences below tolerance should be MATCHED."""
        row = pd.Series({
            'clearing_reference': 'CLR-004',
            'internal_amount':    Decimal('100.00'),
            'clearing_amount':    Decimal('100.004'),  # Within 0.005 tolerance
            'internal_currency':  'GBP',
            'clearing_currency':  'GBP',
        })
        assert service._classify_record(row) == ReconciliationStatus.MATCHED.value


# ── Unit Tests: _reconcile ────────────────────────────────────────────────────

class TestReconcile:

    def test_reconcile_produces_correct_statuses(self, service,
                                                  sample_internal_df,
                                                  sample_clearing_df):
        result = service._reconcile(sample_internal_df, sample_clearing_df)

        assert len(result) == 3

        matched_rows   = result[result['status'] == ReconciliationStatus.MATCHED.value]
        unmatched_rows = result[result['status'] == ReconciliationStatus.UNMATCHED.value]
        exception_rows = result[result['status'] == ReconciliationStatus.EXCEPTION.value]

        assert len(matched_rows)   == 1, "Expected 1 MATCHED record"
        assert len(unmatched_rows) == 1, "Expected 1 UNMATCHED record"
        assert len(exception_rows) == 1, "Expected 1 EXCEPTION record"

    def test_matched_record_reference(self, service, sample_internal_df, sample_clearing_df):
        result = service._reconcile(sample_internal_df, sample_clearing_df)
        matched = result[result['status'] == ReconciliationStatus.MATCHED.value]
        assert matched.iloc[0]['payment_reference'] == 'PAY-20240315-000001-AB12'

    def test_exception_has_discrepancy_amount(self, service, sample_internal_df, sample_clearing_df):
        result = service._reconcile(sample_internal_df, sample_clearing_df)
        exception = result[result['status'] == ReconciliationStatus.EXCEPTION.value]
        assert exception.iloc[0]['discrepancy_amount'] is not None

    def test_exceptions_flagged_for_investigation(self, service, sample_internal_df, sample_clearing_df):
        result = service._reconcile(sample_internal_df, sample_clearing_df)
        exception = result[result['status'] == ReconciliationStatus.EXCEPTION.value]
        assert exception.iloc[0]['requires_investigation'] is True

    def test_empty_internal_returns_empty(self, service, sample_clearing_df):
        empty_df = pd.DataFrame()
        result   = service._reconcile(empty_df, sample_clearing_df)
        assert result.empty


# ── Integration Tests: REST API ───────────────────────────────────────────────

class TestHealthEndpoints:

    def test_liveness_returns_200(self, app):
        with app.test_client() as client:
            res = client.get('/health/liveness')
            assert res.status_code == 200
            data = res.get_json()
            assert data['status'] == 'UP'

    def test_readiness_with_db_up(self, app):
        with app.test_client() as client:
            res = client.get('/health/readiness')
            # SQLite in-memory should be reachable
            assert res.status_code == 200


class TestReconciliationRoutes:

    def test_list_runs_returns_empty_initially(self, app):
        with app.test_client() as client:
            res = client.get('/api/v1/reconciliation/runs')
            assert res.status_code == 200
            assert res.get_json() == []

    def test_get_unknown_run_returns_404(self, app):
        with app.test_client() as client:
            res = client.get('/api/v1/reconciliation/runs/RECON-99999999')
            assert res.status_code == 404

    def test_trigger_with_invalid_date_returns_400(self, app):
        with app.test_client() as client:
            res = client.post(
                '/api/v1/reconciliation/run',
                json={'date': 'not-a-date'},
                content_type='application/json'
            )
            assert res.status_code == 400
            assert res.get_json()['code'] == 'VALIDATION_ERROR'
