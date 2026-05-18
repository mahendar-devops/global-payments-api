"""
app/routes/reports.py
Analytics and reporting endpoints.
Read-heavy — all queries target the reporting replica (read-only connection).
"""

from datetime import date, timedelta
from flask import Blueprint, jsonify, request

from app.config.database import db
from app.models.reconciliation import ReconciliationRun, ReconciliationRecord, ReconciliationStatus

reports_bp = Blueprint('reports', __name__)


# ── GET /api/v1/reports/summary?from=2024-03-01&to=2024-03-31 ────────────────

@reports_bp.route('/summary', methods=['GET'])
def summary():
    """
    Aggregated reconciliation summary for a date range.
    Used by the Finance team's Grafana dashboard.
    """
    from_str = request.args.get('from')
    to_str   = request.args.get('to')

    # Default: last 30 days
    to_date   = date.fromisoformat(to_str)   if to_str   else date.today()
    from_date = date.fromisoformat(from_str) if from_str else to_date - timedelta(days=30)

    if (to_date - from_date).days > 90:
        return jsonify(
            code='VALIDATION_ERROR',
            message='Date range cannot exceed 90 days'
        ), 400

    runs = (
        ReconciliationRun.query
        .filter(ReconciliationRun.run_date >= from_date)
        .filter(ReconciliationRun.run_date <= to_date)
        .filter(ReconciliationRun.status == 'COMPLETED')
        .all()
    )

    if not runs:
        return jsonify({
            'from_date':        str(from_date),
            'to_date':          str(to_date),
            'total_runs':       0,
            'total_records':    0,
            'total_matched':    0,
            'total_unmatched':  0,
            'total_exceptions': 0,
            'avg_match_rate':   0,
        })

    total_records    = sum(r.total_records    for r in runs)
    total_matched    = sum(r.matched_count    for r in runs)
    total_unmatched  = sum(r.unmatched_count  for r in runs)
    total_exceptions = sum(r.exception_count  for r in runs)
    avg_match_rate   = round(total_matched / total_records * 100, 2) if total_records else 0

    return jsonify({
        'from_date':        str(from_date),
        'to_date':          str(to_date),
        'total_runs':       len(runs),
        'total_records':    total_records,
        'total_matched':    total_matched,
        'total_unmatched':  total_unmatched,
        'total_exceptions': total_exceptions,
        'avg_match_rate_pct': avg_match_rate,
        'total_amount_gbp': str(sum(
            r.total_amount_gbp for r in runs if r.total_amount_gbp
        )),
    })


# ── GET /api/v1/reports/exceptions?date=2024-03-15 ──────────────────────────

@reports_bp.route('/exceptions', methods=['GET'])
def exceptions_report():
    """
    Returns all EXCEPTION records for a given date.
    Sent to the Finance Ops team for manual investigation.
    """
    date_str = request.args.get('date')
    if not date_str:
        return jsonify(code='VALIDATION_ERROR', message='date query param is required'), 400

    try:
        run_date   = date.fromisoformat(date_str)
        run_id     = f"RECON-{run_date.strftime('%Y%m%d')}"
    except ValueError:
        return jsonify(code='VALIDATION_ERROR', message='Invalid date format'), 400

    records = (
        ReconciliationRecord.query
        .filter_by(
            reconciliation_run_id=run_id,
            requires_investigation=True
        )
        .order_by(ReconciliationRecord.payment_reference)
        .all()
    )

    return jsonify({
        'run_id':     run_id,
        'date':       date_str,
        'count':      len(records),
        'exceptions': [{
            'payment_reference':  r.payment_reference,
            'internal_amount':    str(r.internal_amount),
            'clearing_amount':    str(r.clearing_amount) if r.clearing_amount else None,
            'discrepancy_amount': str(r.discrepancy_amount) if r.discrepancy_amount else None,
            'notes':              r.notes,
        } for r in records],
    })
