"""app/config/logging.py — Structured JSON logging with structlog."""

import logging
import sys
import structlog
from flask import Flask


def configure_logging(app: Flask) -> None:
    """
    Configure structured JSON logging.
    All logs are JSON in production for CloudWatch/ELK ingestion.
    """
    log_level = logging.DEBUG if app.config.get('DEBUG') else logging.INFO

    # Configure structlog processors
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt='iso'),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            # JSON in production, pretty-print in dev
            structlog.processors.JSONRenderer()
            if not app.config.get('DEBUG')
            else structlog.dev.ConsoleRenderer(colors=True),
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    # Configure standard logging to use structlog
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(log_level)

    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    root_logger.addHandler(handler)

    # Silence noisy libraries
    logging.getLogger('sqlalchemy.engine').setLevel(logging.WARNING)
    logging.getLogger('kafka').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)
