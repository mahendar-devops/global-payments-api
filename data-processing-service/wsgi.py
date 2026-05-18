"""
wsgi.py — Gunicorn entrypoint.

Production command (in Dockerfile):
    gunicorn --config gunicorn.conf.py wsgi:app
"""

from app import create_app
from app.utils.kafka_consumer import start_consumer_thread

app = create_app()

# Start Kafka consumer background thread when the gunicorn worker starts
# Note: In production, this runs as a separate Deployment (different scaling)
# Here it's co-located for simplicity.
with app.app_context():
    start_consumer_thread(app)
