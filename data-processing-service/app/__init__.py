"""
data-processing-service — Flask Application Factory

Handles:
  - Payment reconciliation (daily batch)
  - Transaction analytics and reporting
  - Kafka consumer for payment events
  - REST API for triggering reconciliation and fetching reports
"""

import os
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

from app.config.settings import get_config
from app.config.database import db, migrate
from app.config.logging import configure_logging
from app.routes.reconciliation import reconciliation_bp
from app.routes.reports import reports_bp
from app.routes.health import health_bp


def create_app(config_name: str = None) -> Flask:
    """
    Application factory pattern.
    Allows creating multiple app instances for testing.
    """
    app = Flask(__name__)

    # ── Load Configuration ────────────────────────────────────────
    config = get_config(config_name or os.environ.get('FLASK_ENV', 'production'))
    app.config.from_object(config)

    # ── Structured Logging ────────────────────────────────────────
    configure_logging(app)

    # ── Database ──────────────────────────────────────────────────
    db.init_app(app)
    migrate.init_app(app, db)

    # ── Prometheus Metrics ────────────────────────────────────────
    # Exposes /metrics endpoint automatically
    metrics = PrometheusMetrics(app, default_labels={
        'service':     'data-processing-service',
        'environment': app.config.get('ENVIRONMENT', 'production'),
    })
    metrics.info('app_info', 'Application info',
                 version=app.config.get('VERSION', '1.0.0'))

    # ── Blueprints ────────────────────────────────────────────────
    app.register_blueprint(health_bp,          url_prefix='/health')
    app.register_blueprint(reconciliation_bp,  url_prefix='/api/v1/reconciliation')
    app.register_blueprint(reports_bp,         url_prefix='/api/v1/reports')

    # ── Error Handlers ────────────────────────────────────────────
    register_error_handlers(app)

    return app


def register_error_handlers(app: Flask) -> None:
    """Register consistent JSON error responses."""

    @app.errorhandler(400)
    def bad_request(e):
        return jsonify(code='BAD_REQUEST', message=str(e)), 400

    @app.errorhandler(404)
    def not_found(e):
        return jsonify(code='NOT_FOUND', message='Resource not found'), 404

    @app.errorhandler(422)
    def unprocessable(e):
        return jsonify(code='UNPROCESSABLE_ENTITY', message=str(e)), 422

    @app.errorhandler(500)
    def internal_error(e):
        app.logger.error('Unhandled exception: %s', str(e), exc_info=True)
        return jsonify(
            code='INTERNAL_ERROR',
            message='An unexpected error occurred. Please contact support.'
        ), 500
