# ─────────────────────────────────────────────────────────────────
# gateway-service/Dockerfile
# Multi-stage build: Dependencies → Runtime (production only)
# ─────────────────────────────────────────────────────────────────

# ── Stage 1: DEPENDENCY INSTALL ──────────────────────────────────
# Uses full Node image to install all deps (including devDependencies for now).
FROM node:20-alpine AS deps

WORKDIR /app

# Copy lock file first for layer caching
COPY package.json package-lock.json ./

# Install production + dev dependencies (needed for build steps if any)
RUN npm ci --ignore-scripts

# ── Stage 2: RUNTIME ─────────────────────────────────────────────
# Clean production image — only production dependencies.
FROM node:20-alpine AS runtime

# Install dumb-init for proper signal handling in containers
RUN apk add --no-cache dumb-init curl

# Security: non-root user
RUN addgroup -S gateway && \
    adduser  -S gateway -G gateway -u 1001

WORKDIR /app

# Copy only production dependencies from deps stage
COPY package.json package-lock.json ./
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# Copy application source
COPY --chown=gateway:gateway src/ ./src/

USER gateway

# Build metadata
ARG BUILD_VERSION=unknown
ARG GIT_COMMIT=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.title="gateway-service"         \
      org.opencontainers.image.version="${BUILD_VERSION}"       \
      org.opencontainers.image.revision="${GIT_COMMIT}"         \
      org.opencontainers.image.created="${BUILD_TIMESTAMP}"     \
      org.opencontainers.image.vendor="GlobalPayments"          \
      org.opencontainers.image.description="API Gateway Service"

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=15s \
    CMD curl -f http://localhost:3000/health/liveness || exit 1

EXPOSE 3000

ENV NODE_ENV=production \
    PORT=3000

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/app.js"]
