"""
app/models/reconciliation.py
SQLAlchemy models for the reconciliation reporting database.
This service has its own read-optimised schema — separate from
the payments-service transactional DB.
"""

from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum as PyEnum

from sqlalchemy import (Column, String, BigInteger, Numeric, DateTime,
                        Enum, Integer, Text, Boolean, Index)
from sqlalchemy.dialects.postgresql import UUID
import uuid

from app.config.database import db


class ReconciliationStatus(PyEnum):
    MATCHED   = 'MATCHED'    # Internal record matches clearing network
    UNMATCHED = 'UNMATCHED'  # No matching record found
    EXCEPTION = 'EXCEPTION'  # Amounts or details differ


class ReconciliationRecord(db.Model):
    """
    One row per payment in the daily reconciliation run.
    Compares the payments-service ledger against the clearing network's report.
    """
    __tablename__ = 'reconciliation_records'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Foreign key to the payments-service (logical reference — no FK constraint
    # across service databases)
    payment_reference   = Column(String(30), nullable=False, index=True)
    payment_id          = Column(UUID(as_uuid=True), nullable=False)

    # Internal ledger values (from payments-service)
    internal_amount     = Column(Numeric(18, 2), nullable=False)
    internal_currency   = Column(String(3), nullable=False)
    internal_status     = Column(String(20), nullable=False)
    internal_created_at = Column(DateTime(timezone=True), nullable=False)

    # External clearing network values (from the reconciliation file)
    clearing_amount     = Column(Numeric(18, 2))
    clearing_currency   = Column(String(3))
    clearing_reference  = Column(String(50))
    clearing_status     = Column(String(20))
    clearing_settled_at = Column(DateTime(timezone=True))

    # Reconciliation result
    status              = Column(Enum(ReconciliationStatus), nullable=False,
                                 default=ReconciliationStatus.UNMATCHED)
    discrepancy_amount  = Column(Numeric(18, 2))   # Difference if EXCEPTION
    notes               = Column(Text)

    # Batch tracking
    reconciliation_run_id = Column(String(50), nullable=False, index=True)
    reconciled_at         = Column(DateTime(timezone=True),
                                   default=lambda: datetime.now(timezone.utc))
    requires_investigation = Column(Boolean, default=False)

    __table_args__ = (
        Index('idx_recon_payment_ref',   'payment_reference'),
        Index('idx_recon_run_id',        'reconciliation_run_id'),
        Index('idx_recon_status',        'status'),
        Index('idx_recon_investigation', 'requires_investigation'),
    )

    def __repr__(self):
        return (f'<ReconciliationRecord ref={self.payment_reference} '
                f'status={self.status}>')


class ReconciliationRun(db.Model):
    """
    Metadata for each reconciliation batch execution.
    """
    __tablename__ = 'reconciliation_runs'

    id              = Column(String(50), primary_key=True)  # e.g. RECON-20240315
    run_date        = Column(DateTime(timezone=True), nullable=False)
    started_at      = Column(DateTime(timezone=True),
                             default=lambda: datetime.now(timezone.utc))
    completed_at    = Column(DateTime(timezone=True))
    total_records   = Column(Integer, default=0)
    matched_count   = Column(Integer, default=0)
    unmatched_count = Column(Integer, default=0)
    exception_count = Column(Integer, default=0)
    total_amount_gbp = Column(Numeric(20, 2), default=Decimal('0'))
    status          = Column(String(20), default='RUNNING')  # RUNNING, COMPLETED, FAILED
    error_message   = Column(Text)

    @property
    def match_rate(self) -> float:
        if not self.total_records:
            return 0.0
        return round(self.matched_count / self.total_records * 100, 2)

    def __repr__(self):
        return f'<ReconciliationRun {self.id} status={self.status}>'
