"""
app/config/settings.py
Configuration classes for each deployment environment.
Sensitive values are NEVER hardcoded — injected from AWS Secrets Manager.
"""

import os
from datetime import timedelta


class BaseConfig:
    """Settings common to all environments."""

    # Flask
    SECRET_KEY      = os.environ.get('SECRET_KEY', os.urandom(32))
    JSON_SORT_KEYS  = False
    PROPAGATE_EXCEPTIONS = True

    # Database — URL injected from Secrets Manager
    SQLALCHEMY_DATABASE_URI         = os.environ.get('DATABASE_URL')
    SQLALCHEMY_TRACK_MODIFICATIONS  = False
    SQLALCHEMY_ENGINE_OPTIONS       = {
        'pool_size':         5,
        'max_overflow':      10,
        'pool_pre_ping':     True,   # Detect stale connections
        'pool_recycle':      1800,   # Recycle connections every 30 min
        'connect_args': {
            'connect_timeout': 10,
            'application_name': 'data-processing-service',
        },
    }

    # Kafka
    KAFKA_BOOTSTRAP_SERVERS  = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
    KAFKA_GROUP_ID           = 'data-processing-service'
    KAFKA_PAYMENT_TOPIC      = 'payment-events'
    KAFKA_AUTO_OFFSET_RESET  = 'earliest'

    # AWS
    AWS_REGION          = os.environ.get('AWS_REGION', 'eu-west-2')
    S3_REPORTS_BUCKET   = os.environ.get('S3_REPORTS_BUCKET', 'payments-reports-dev')

    # App
    ENVIRONMENT = os.environ.get('ENVIRONMENT', 'production')
    VERSION     = os.environ.get('APP_VERSION', '1.0.0')

    # Reconciliation
    RECONCILIATION_BATCH_SIZE   = int(os.environ.get('RECON_BATCH_SIZE', '1000'))
    RECONCILIATION_LOOKBACK_DAYS = int(os.environ.get('RECON_LOOKBACK_DAYS', '2'))


class DevelopmentConfig(BaseConfig):
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        'DATABASE_URL', 'postgresql://dev_user:devpassword@localhost:5432/payments_reporting')
    SQLALCHEMY_ENGINE_OPTIONS = {
        **BaseConfig.SQLALCHEMY_ENGINE_OPTIONS,
        'echo': True,  # Log SQL in development
    }


class TestingConfig(BaseConfig):
    TESTING  = True
    DEBUG    = True
    # Use in-memory SQLite for unit tests (fast, no external dependency)
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    # Disable Kafka in tests
    KAFKA_BOOTSTRAP_SERVERS = None


class ProductionConfig(BaseConfig):
    DEBUG   = False
    TESTING = False

    # Enforce that DATABASE_URL is set
    @classmethod
    def init_app(cls, app):
        BaseConfig.init_app(app) if hasattr(BaseConfig, 'init_app') else None
        assert os.environ.get('DATABASE_URL'), \
            'DATABASE_URL must be set in production'
        assert os.environ.get('KAFKA_BOOTSTRAP_SERVERS'), \
            'KAFKA_BOOTSTRAP_SERVERS must be set in production'


_config_map = {
    'development': DevelopmentConfig,
    'testing':     TestingConfig,
    'production':  ProductionConfig,
    'local':       DevelopmentConfig,
    'test':        TestingConfig,
}


def get_config(env_name: str):
    config = _config_map.get(env_name, ProductionConfig)
    return config
