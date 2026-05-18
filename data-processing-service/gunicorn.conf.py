# gunicorn.conf.py — Production Gunicorn configuration

import multiprocessing
import os

# ── Workers ────────────────────────────────────────────────────────────────
# Formula: (2 × CPU_cores) + 1 — good for I/O-bound workloads
# In a container with 1 CPU: 3 workers
workers      = int(os.environ.get('GUNICORN_WORKERS',
                                   multiprocessing.cpu_count() * 2 + 1))
worker_class = 'sync'       # Sync for SQLAlchemy thread-safety
threads      = 1            # 1 thread per sync worker

# ── Networking ─────────────────────────────────────────────────────────────
bind         = f"0.0.0.0:{os.environ.get('PORT', '5000')}"
backlog      = 512

# ── Timeouts ───────────────────────────────────────────────────────────────
timeout           = 60      # Kill workers that take > 60s (prevents stale workers)
graceful_timeout  = 30      # Graceful shutdown window on SIGTERM
keepalive         = 5

# ── Logging ────────────────────────────────────────────────────────────────
loglevel      = os.environ.get('LOG_LEVEL', 'info')
accesslog     = '-'         # stdout — collected by Kubernetes/CloudWatch
errorlog      = '-'         # stderr
access_log_format = (
    '{"time":"%(t)s","method":"%(m)s","path":"%(U)s","status":%(s)s,'
    '"duration_ms":%(M)s,"bytes":%(b)s,"remote":%(h)s}'
)

# ── Process ────────────────────────────────────────────────────────────────
preload_app  = True         # Load app once before forking workers (saves memory)
daemon       = False        # Never daemonise in containers

# ── Hooks ──────────────────────────────────────────────────────────────────
def on_starting(server):
    server.log.info("Gunicorn starting — data-processing-service")

def worker_exit(server, worker):
    """Cleanup on worker exit — close DB connections."""
    from app.config.database import db
    try:
        db.engine.dispose()
    except Exception:
        pass
