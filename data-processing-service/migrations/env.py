"""
migrations/env.py — Alembic migration environment.

Reads DATABASE_URL from the environment so the same migration scripts
work across dev, QA, and prod without modification.
"""

import os
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

# Bring Flask app models into scope so Alembic can detect schema changes
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app import create_app
from app.config.database import db

# Alembic Config object — access to alembic.ini values
config = context.config

# Override sqlalchemy.url with the DATABASE_URL environment variable
database_url = os.environ.get('DATABASE_URL')
if database_url:
    config.set_main_option('sqlalchemy.url', database_url)

# Setup Python logging from alembic.ini
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# MetaData for autogenerate — points to our SQLAlchemy models
flask_app   = create_app('production')
target_metadata = db.metadata


def run_migrations_offline() -> None:
    """
    Run migrations without a database connection.
    Outputs SQL to stdout — useful for DBAs to review before applying.
    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,          # Detect column type changes
        compare_server_default=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """
    Run migrations against a live database connection.
    Uses a connection pool appropriate for a migration context (NullPool).
    """
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,     # No pooling during migrations
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
