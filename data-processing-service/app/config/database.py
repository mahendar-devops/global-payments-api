"""app/config/database.py — SQLAlchemy + Flask-Migrate setup."""

from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate

db      = SQLAlchemy()
migrate = Migrate()
