# ─────────────────────────────────────────────────────────────────
# payments-service/Dockerfile
# Multi-stage build: Builder (JDK) → Runtime (JRE-only)
# Final image has ~60% smaller attack surface vs single-stage.
# Trivy will scan this image in the Jenkins pipeline.
# ─────────────────────────────────────────────────────────────────

# ── Stage 1: BUILD ───────────────────────────────────────────────
FROM eclipse-temurin:17-jdk-alpine AS builder

WORKDIR /workspace

# Cache Maven dependencies separately from source (Docker layer cache).
# The `mvn dependency:go-offline` layer is only invalidated when pom.xml changes —
# not on every source code change. This saves ~2 minutes per build.
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
RUN chmod +x ./mvnw && \
    ./mvnw dependency:go-offline -B -q

# Now copy source and build the JAR
COPY src ./src
RUN ./mvnw package -DskipTests -B -q && \
    # Explode the layered JAR for faster container startup
    mkdir -p target/extracted && \
    java -Djarmode=layertools -jar target/*.jar extract --destination target/extracted

# ── Stage 2: RUNTIME ─────────────────────────────────────────────
# JRE-only — no compiler, no javac, no JDK tools.
# Alpine base keeps image small; Temurin is the recommended OpenJDK distribution.
FROM eclipse-temurin:17-jre-alpine AS runtime

# Install only what's strictly needed
RUN apk add --no-cache \
    curl \        
    dumb-init     # PID 1 process manager — handles signals correctly in containers

# Security: create a dedicated non-root user
RUN addgroup -S payments && \
    adduser  -S payments -G payments -u 1001

WORKDIR /app

# Copy exploded layered JAR in order of least-to-most frequently changed.
# Docker layer caching means only the 'application' layer rebuilds on code change.
COPY --from=builder --chown=payments:payments \
     /workspace/target/extracted/dependencies/          ./
COPY --from=builder --chown=payments:payments \
     /workspace/target/extracted/spring-boot-loader/    ./
COPY --from=builder --chown=payments:payments \
     /workspace/target/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=payments:payments \
     /workspace/target/extracted/application/           ./

USER payments

# Build-time metadata for audit trail (populated by Jenkins via --build-arg)
ARG BUILD_VERSION=unknown
ARG GIT_COMMIT=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.title="payments-service"                  \
      org.opencontainers.image.version="${BUILD_VERSION}"                 \
      org.opencontainers.image.revision="${GIT_COMMIT}"                  \
      org.opencontainers.image.created="${BUILD_TIMESTAMP}"               \
      org.opencontainers.image.vendor="GlobalPayments"                   \
      org.opencontainers.image.description="Core Payments Microservice"

# Kubernetes liveness/readiness probe target
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=60s \
    CMD curl -f http://localhost:8080/actuator/health/liveness || exit 1

EXPOSE 8080

# dumb-init ensures proper signal handling (SIGTERM on pod shutdown)
ENTRYPOINT ["dumb-init", "--"]
CMD ["java", \
     "-XX:+UseContainerSupport",       \
     "-XX:MaxRAMPercentage=75.0",       \
     "-XX:+ExitOnOutOfMemoryError",     \
     "-Djava.security.egd=file:/dev/./urandom", \
     "-Dspring.profiles.active=${SPRING_PROFILES_ACTIVE:-production}", \
     "org.springframework.boot.loader.launch.JarLauncher"]
