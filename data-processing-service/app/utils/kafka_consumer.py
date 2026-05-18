"""
app/utils/kafka_consumer.py

Kafka consumer for real-time payment events.
Listens to the 'payment-events' topic and maintains a running
analytics summary in the reporting database.

Runs as a background thread started alongside the Flask app.
In production, this would be a separate Kubernetes Deployment
(the consumer and the API server scale independently).
"""

import threading
import signal
import structlog
from confluent_kafka import Consumer, KafkaError, KafkaException
import json
from datetime import datetime, timezone

logger = structlog.get_logger(__name__)

_consumer_thread = None
_running = False


class PaymentEventConsumer:
    """
    Consumes payment events from Kafka and updates analytics counters.

    Consumer group: data-processing-service
    Topic:          payment-events
    Offset policy:  earliest (process all events from the beginning on new consumer)
    """

    def __init__(self, bootstrap_servers: str, group_id: str, topic: str):
        self.topic  = topic
        self.logger = structlog.get_logger(__name__)

        self.consumer = Consumer({
            'bootstrap.servers':        bootstrap_servers,
            'group.id':                 group_id,
            'auto.offset.reset':        'earliest',
            'enable.auto.commit':       False,   # Manual commit — at-least-once semantics
            'max.poll.interval.ms':     300000,
            'session.timeout.ms':       30000,
            'heartbeat.interval.ms':    10000,
        })

    def start(self, app_context) -> None:
        """Start consuming in the current thread (blocking)."""
        global _running
        _running = True

        self.consumer.subscribe([self.topic])
        self.logger.info('Kafka consumer started', topic=self.topic)

        try:
            while _running:
                msg = self.consumer.poll(timeout=1.0)

                if msg is None:
                    continue

                if msg.error():
                    if msg.error().code() == KafkaError._PARTITION_EOF:
                        # Reached end of partition — normal, keep polling
                        continue
                    self.logger.error('Kafka consumer error', error=str(msg.error()))
                    continue

                try:
                    with app_context:
                        self._process_message(msg)
                    # Commit offset only after successful processing
                    self.consumer.commit(asynchronous=False)

                except Exception as exc:
                    self.logger.error('Failed to process Kafka message',
                                      offset=msg.offset(),
                                      partition=msg.partition(),
                                      error=str(exc),
                                      exc_info=True)
                    # Don't commit — message will be reprocessed on restart
                    # In production: after N failures, send to a Dead Letter Topic

        except KafkaException as exc:
            self.logger.error('Kafka consumer fatal error', error=str(exc))
        finally:
            self.consumer.close()
            self.logger.info('Kafka consumer closed')

    def _process_message(self, msg) -> None:
        """Parse and handle a single payment event."""
        try:
            event = json.loads(msg.value().decode('utf-8'))
        except json.JSONDecodeError as exc:
            self.logger.warning('Malformed Kafka message — skipping',
                                offset=msg.offset(), error=str(exc))
            return

        event_type = event.get('eventType')
        payment_id = event.get('paymentId', 'unknown')
        status     = event.get('status', 'unknown')

        self.logger.info('Processing payment event',
                         event_type=event_type,
                         payment_id=payment_id,
                         status=status)

        # Route to handler based on event type
        handlers = {
            'PAYMENT_CREATED':        self._handle_payment_created,
            'PAYMENT_STATUS_CHANGED': self._handle_status_changed,
            'PAYMENT_RETRY':          self._handle_payment_retry,
        }

        handler = handlers.get(event_type)
        if handler:
            handler(event)
        else:
            self.logger.debug('Unhandled event type — skipping', event_type=event_type)

    def _handle_payment_created(self, event: dict) -> None:
        """
        Record payment creation for analytics.
        Could update a real-time dashboard counter in Redis.
        """
        self.logger.info('Payment created event received',
                         payment_id=event.get('paymentId'),
                         amount=event.get('amount'),
                         currency=event.get('currency'))
        # In a full implementation: update DailyStats counter in DB

    def _handle_status_changed(self, event: dict) -> None:
        """
        Handle terminal state transitions for SLA tracking.
        """
        status     = event.get('status')
        payment_id = event.get('paymentId')

        self.logger.info('Payment status changed',
                         payment_id=payment_id, status=status)

        if status == 'COMPLETED':
            # Track settlement time for SLA reporting
            pass
        elif status == 'FAILED':
            # Increment failure counter — alert if rate exceeds threshold
            pass

    def _handle_payment_retry(self, event: dict) -> None:
        self.logger.info('Payment retry event',
                         payment_id=event.get('paymentId'))


# ── Thread management ─────────────────────────────────────────────────────────

def start_consumer_thread(app) -> None:
    """Start the Kafka consumer in a background daemon thread."""
    global _consumer_thread, _running

    cfg = app.config
    if not cfg.get('KAFKA_BOOTSTRAP_SERVERS'):
        logger.warning('Kafka not configured — consumer will not start')
        return

    consumer = PaymentEventConsumer(
        bootstrap_servers=cfg['KAFKA_BOOTSTRAP_SERVERS'],
        group_id=cfg['KAFKA_GROUP_ID'],
        topic=cfg['KAFKA_PAYMENT_TOPIC'],
    )

    _consumer_thread = threading.Thread(
        target=consumer.start,
        args=(app.app_context(),),
        daemon=True,          # Dies when the main process exits
        name='kafka-consumer',
    )
    _consumer_thread.start()
    logger.info('Kafka consumer thread started')


def stop_consumer() -> None:
    """Signal the consumer to stop gracefully."""
    global _running
    _running = False
    logger.info('Kafka consumer stop signal sent')
