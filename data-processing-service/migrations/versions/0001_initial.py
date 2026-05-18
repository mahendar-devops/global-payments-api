"""Create reconciliation tables

Revision ID: 0001_initial
Revises:
Create Date: 2024-03-15 10:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '0001_initial'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── reconciliation_runs ────────────────────────────────────────────────
    op.create_table(
        'reconciliation_runs',
        sa.Column('id',               sa.String(50),       primary_key=True),
        sa.Column('run_date',         sa.DateTime(timezone=True), nullable=False),
        sa.Column('started_at',       sa.DateTime(timezone=True)),
        sa.Column('completed_at',     sa.DateTime(timezone=True)),
        sa.Column('total_records',    sa.Integer(),        server_default='0'),
        sa.Column('matched_count',    sa.Integer(),        server_default='0'),
        sa.Column('unmatched_count',  sa.Integer(),        server_default='0'),
        sa.Column('exception_count',  sa.Integer(),        server_default='0'),
        sa.Column('total_amount_gbp', sa.Numeric(20, 2),   server_default='0'),
        sa.Column('status',           sa.String(20),       server_default='RUNNING'),
        sa.Column('error_message',    sa.Text()),
    )
    op.create_index('idx_runs_run_date', 'reconciliation_runs', ['run_date'])
    op.create_index('idx_runs_status',   'reconciliation_runs', ['status'])

    # ── reconciliation_records ─────────────────────────────────────────────
    op.create_table(
        'reconciliation_records',
        sa.Column('id',                     postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('payment_reference',      sa.String(30),  nullable=False),
        sa.Column('payment_id',             postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('internal_amount',        sa.Numeric(18, 2), nullable=False),
        sa.Column('internal_currency',      sa.String(3),   nullable=False),
        sa.Column('internal_status',        sa.String(20),  nullable=False),
        sa.Column('internal_created_at',    sa.DateTime(timezone=True), nullable=False),
        sa.Column('clearing_amount',        sa.Numeric(18, 2)),
        sa.Column('clearing_currency',      sa.String(3)),
        sa.Column('clearing_reference',     sa.String(50)),
        sa.Column('clearing_status',        sa.String(20)),
        sa.Column('clearing_settled_at',    sa.DateTime(timezone=True)),
        sa.Column('status',                 sa.String(20),  nullable=False, server_default='UNMATCHED'),
        sa.Column('discrepancy_amount',     sa.Numeric(18, 2)),
        sa.Column('notes',                  sa.Text()),
        sa.Column('reconciliation_run_id',  sa.String(50),  nullable=False),
        sa.Column('reconciled_at',          sa.DateTime(timezone=True)),
        sa.Column('requires_investigation', sa.Boolean(),   server_default='false'),
    )
    op.create_index('idx_recon_payment_ref',   'reconciliation_records', ['payment_reference'])
    op.create_index('idx_recon_run_id',        'reconciliation_records', ['reconciliation_run_id'])
    op.create_index('idx_recon_status',        'reconciliation_records', ['status'])
    op.create_index('idx_recon_investigation', 'reconciliation_records', ['requires_investigation'])


def downgrade() -> None:
    op.drop_table('reconciliation_records')
    op.drop_table('reconciliation_runs')
