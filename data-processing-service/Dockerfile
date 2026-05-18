# ─────────────────────────────────────────────────────────────────
# data-processing-service/Dockerfile
# Multi-stage build: Builder (with build tools) → Runtime (slim)
# ─────────────────────────────────────────────────────────────────

# ── Stage 1: BUILD ───────────────────────────────────────────────
# Full Python image needed to compile native extensions (psycopg2, numpy)
FROM python:3.12-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Upgrade pip and install wheel — required to build native packages
RUN pip install --upgrade pip wheel

# Install Python dependencies into a target directory
# This lets us copy only the compiled packages to the runtime stage
COPY requirements.txt .
RUN pip install --no-cache-dir \
    --prefix=/install \
    -r requirements.txt

# ── Stage 2: RUNTIME ─────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Only the runtime libraries needed by psycopg2 and numpy
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    dumb-init \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd -r dataproc && \
    useradd -r -g dataproc -u 1001 dataproc

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY --chown=dataproc:dataproc app/         ./app/
COPY --chown=dataproc:dataproc wsgi.py      ./
COPY --chown=dataproc:dataproc gunicorn.conf.py ./

USER dataproc

# Build metadata
ARG BUILD_VERSION=unknown
ARG GIT_COMMIT=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.title="data-processing-service"          \
      org.opencontainers.image.version="${BUILD_VERSION}"                \
      org.opencontainers.image.revision="${GIT_COMMIT}"                  \
      org.opencontainers.image.created="${BUILD_TIMESTAMP}"              \
      org.opencontainers.image.vendor="GlobalPayments"                   \
      org.opencontainers.image.description="Payment Reconciliation Service"

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
    CMD curl -f http://localhost:5000/health/liveness || exit 1

EXPOSE 5000

ENV FLASK_ENV=production \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1

ENTRYPOINT ["dumb-init", "--"]
CMD ["gunicorn", "--config", "gunicorn.conf.py", "wsgi:app"]
