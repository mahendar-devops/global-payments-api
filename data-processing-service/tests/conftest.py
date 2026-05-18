"""
tests/conftest.py
Shared pytest fixtures for the data-processing-service test suite.

Provides:
  - Flask test app (in-memory SQLite, no Kafka)
  - Database session with rollback after each test
  - Pre-built sample DataFrames for reconciliation tests
  - Mock S3 client factory
  - Factory functions for creating test DB records
"""

import pytest
import pandas as pd
from decimal import Decimal
from datetime import date, datetime, timezone
from unittest.mock import MagicMock

from app import create_app
from app.config.database import db as _db
from app.models.reconciliation import (
    ReconciliationRun, ReconciliationRecord, ReconciliationStatus
)


# ── App + DB Fixtures ─────────────────────────────────────────────────────────

@pytest.fixture(scope="session")
def app():
    """
    Session-scoped Flask app using in-memory SQLite.
    Created once per test session — faster than per-test.
    """
    application = create_app("testing")

    with application.app_context():
        _db.create_all()
        yield application
        _db.drop_all()


@pytest.fixture(scope="session")
def client(app):
    """Flask test client — reused across the session."""
    return app.test_client()


@pytest.fixture(autouse=True)
def db_rollback(app):
    """
    Rolls back the DB transaction after every test.
    Ensures test isolation without dropping/recreating tables.
    """
    with app.app_context():
        connection = _db.engine.connect()
        transaction = connection.begin()

        yield

        transaction.rollback()
        connection.close()


@pytest.fixture
def db_session(app):
    """Direct access to the SQLAlchemy session for fixture factories."""
    with app.app_context():
        yield _db.session


# ── Mock Factories ────────────────────────────────────────────────────────────

@pytest.fixture
def mock_s3_client():
    """
    Pre-configured mock S3 client.
    Tests that need S3 interactions inject this fixture and configure
    return values as needed.
    """
    client = MagicMock()
    # Default: GetObject raises NoSuchKey (clearing file not found)
    client.exceptions.NoSuchKey = Exception
    client.get_object.side_effect = Exception("NoSuchKey")
    return client


@pytest.fixture
def reconciliation_service(app, mock_s3_client):
    """ReconciliationService with mocked S3 client, inside app context."""
    from app.services.reconciliation_service import ReconciliationService

    with app.app_context():
        service = ReconciliationService(
            s3_bucket="test-bucket",
            aws_region="eu-west-2",
        )
        service.s3_client = mock_s3_client
        yield service


# ── Data Fixtures ─────────────────────────────────────────────────────────────

@pytest.fixture
def sample_internal_df():
    """
    Realistic internal payments DataFrame matching what
    _load_internal_payments() would return from the DB.
    """
    return pd.DataFrame([
        {
            "payment_reference":   "PAY-20240315-000001-AB12",
            "payment_id":          "aaa-111-aaa-111-aaa111",
            "amount_minor_units":  10000,
            "currency":            "GBP",
            "status":              "COMPLETED",
            "clearing_reference":  "CLR-INTERNAL-001",
            "created_at":          "2024-03-15T10:00:00Z",
            "internal_amount":     Decimal("100.00"),
            "internal_currency":   "GBP",
            "internal_status":     "COMPLETED",
            "internal_created_at": pd.Timestamp("2024-03-15T10:00:00Z"),
        },
        {
            "payment_reference":   "PAY-20240315-000002-CD34",
            "payment_id":          "bbb-222-bbb-222-bbb222",
            "amount_minor_units":  25050,
            "currency":            "GBP",
            "status":              "COMPLETED",
            "clearing_reference":  "CLR-INTERNAL-002",
            "created_at":          "2024-03-15T11:00:00Z",
            "internal_amount":     Decimal("250.50"),
            "internal_currency":   "GBP",
            "internal_status":     "COMPLETED",
            "internal_created_at": pd.Timestamp("2024-03-15T11:00:00Z"),
        },
        {
            # This payment has no clearing record → UNMATCHED
            "payment_reference":   "PAY-20240315-000003-EF56",
            "payment_id":          "ccc-333-ccc-333-ccc333",
            "amount_minor_units":  5000,
            "currency":            "GBP",
            "status":              "COMPLETED",
            "clearing_reference":  None,
            "created_at":          "2024-03-15T12:00:00Z",
            "internal_amount":     Decimal("50.00"),
            "internal_currency":   "GBP",
            "internal_status":     "COMPLETED",
            "internal_created_at": pd.Timestamp("2024-03-15T12:00:00Z"),
        },
    ])


@pytest.fixture
def sample_clearing_df():
    """
    Clearing network settlement file DataFrame.
    - Record 1: exact match with internal
    - Record 2: amount mismatch → EXCEPTION
    - Record 3: absent (PAY-000003 not in clearing) → UNMATCHED
    """
    return pd.DataFrame([
        {
            "payment_reference":   "PAY-20240315-000001-AB12",
            "clearing_amount":     Decimal("100.00"),    # Exact match
            "clearing_currency":   "GBP",
            "clearing_reference":  "CLR-NET-BANK-001",
            "clearing_status":     "SETTLED",
            "clearing_settled_at": pd.Timestamp("2024-03-15T23:00:00Z"),
        },
        {
            "payment_reference":   "PAY-20240315-000002-CD34",
            "clearing_amount":     Decimal("999.99"),    # Amount mismatch → EXCEPTION
            "clearing_currency":   "GBP",
            "clearing_reference":  "CLR-NET-BANK-002",
            "clearing_status":     "SETTLED",
            "clearing_settled_at": pd.Timestamp("2024-03-15T23:01:00Z"),
        },
    ])


@pytest.fixture
def sample_matched_df(sample_internal_df, sample_clearing_df, reconciliation_service):
    """Pre-reconciled DataFrame with status column populated."""
    return reconciliation_service._reconcile(sample_internal_df, sample_clearing_df)


# ── DB Record Factories ───────────────────────────────────────────────────────

@pytest.fixture
def make_reconciliation_run(db_session):
    """
    Factory for creating ReconciliationRun records in the DB.
    Usage: run = make_reconciliation_run(status="COMPLETED", matched_count=10)
    """
    def _factory(**kwargs):
        defaults = {
            "id":             "RECON-20240315",
            "run_date":       datetime(2024, 3, 15, tzinfo=timezone.utc),
            "status":         "COMPLETED",
            "total_records":  3,
            "matched_count":  1,
            "unmatched_count": 1,
            "exception_count": 1,
            "total_amount_gbp": Decimal("400.50"),
        }
        defaults.update(kwargs)
        run = ReconciliationRun(**defaults)
        db_session.add(run)
        db_session.flush()
        return run
    return _factory


@pytest.fixture
def make_reconciliation_record(db_session):
    """
    Factory for creating ReconciliationRecord records in the DB.
    Usage: record = make_reconciliation_record(status=ReconciliationStatus.EXCEPTION)
    """
    import uuid

    def _factory(**kwargs):
        defaults = {
            "id":                      uuid.uuid4(),
            "payment_reference":       "PAY-20240315-000001-AB12",
            "payment_id":              uuid.uuid4(),
            "internal_amount":         Decimal("100.00"),
            "internal_currency":       "GBP",
            "internal_status":         "COMPLETED",
            "internal_created_at":     datetime(2024, 3, 15, 10, 0, tzinfo=timezone.utc),
            "clearing_amount":         Decimal("100.00"),
            "clearing_reference":      "CLR-NET-001",
            "clearing_status":         "SETTLED",
            "status":                  ReconciliationStatus.MATCHED,
            "reconciliation_run_id":   "RECON-20240315",
            "requires_investigation":  False,
        }
        defaults.update(kwargs)
        record = ReconciliationRecord(**defaults)
        db_session.add(record)
        db_session.flush()
        return record
    return _factory
