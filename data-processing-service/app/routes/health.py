"""
app/routes/health.py
Kubernetes liveness and readiness probe endpoints.
"""

import time
from flask import Blueprint, jsonify, current_app
from app.config.database import db

health_bp  = Blueprint('health', __name__)
START_TIME = time.time()


@health_bp.route('/liveness', methods=['GET'])
def liveness():
    """
    Liveness: is the process alive?
    Returns 200 as long as the Flask process is running.
    """
    return jsonify({
        'status':    'UP',
        'service':   'data-processing-service',
        'uptime_s':  round(time.time() - START_TIME, 1),
    }), 200


@health_bp.route('/readiness', methods=['GET'])
def readiness():
    """
    Readiness: can this pod serve traffic?
    Checks DB connectivity. Kubernetes removes the pod from the
    Service endpoints if this returns non-2xx.
    """
    checks = {}

    # Database check
    try:
        db.session.execute(db.text('SELECT 1'))
        checks['database'] = 'UP'
    except Exception as exc:
        current_app.logger.error('DB health check failed: %s', exc)
        checks['database'] = 'DOWN'

    overall = 'UP' if all(v == 'UP' for v in checks.values()) else 'DOWN'
    status_code = 200 if overall == 'UP' else 503

    return jsonify({'status': overall, 'checks': checks}), status_code


@health_bp.route('/', methods=['GET'])
def root():
    return jsonify({'status': 'UP'}), 200
