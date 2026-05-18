# 🏦 Global Payments API — Microservices Source Code

> **Banking-grade microservices for the Global Payments API platform.**  
> Java Spring Boot · Node.js Express · Python Flask · AWS EKS · Kafka · PostgreSQL

---

## Repository Structure

```
microservices/
├── payments-service/            ← Java 17 / Spring Boot 3 — Core payment processing
│   ├── src/
│   │   ├── main/java/com/globalpayments/paymentsservice/
│   │   │   ├── controller/      PaymentController.java
│   │   │   ├── service/         PaymentService.java
│   │   │   ├── repository/      PaymentRepository.java
│   │   │   ├── model/
│   │   │   │   ├── entity/      Payment.java
│   │   │   │   ├── dto/         PaymentDtos.java
│   │   │   │   └── enums/       PaymentStatus, PaymentType, Currency
│   │   │   ├── security/        SecurityConfig.java (JWT)
│   │   │   └── exception/       GlobalExceptionHandler.java
│   │   └── resources/
│   │       ├── application.yml
│   │       └── db/migration/    V1__create_payments_table.sql  (Flyway)
│   ├── src/test/                Integration tests (Testcontainers + EmbeddedKafka)
│   ├── k8s/deployment.yaml      Deployment, Service, HPA, PDB, ServiceAccount
│   ├── Dockerfile               Multi-stage JDK→JRE build
│   └── pom.xml
│
├── gateway-service/             ← Node.js 20 / Express — API Gateway
│   ├── src/
│   │   ├── app.js               Application entry point
│   │   ├── config/
│   │   │   ├── logger.js        Winston structured logging
│   │   │   └── metrics.js       Prometheus metrics
│   │   ├── middleware/
│   │   │   ├── auth.js          JWT validation + RBAC
│   │   │   ├── rateLimiter.js   Rate limiting (100 req/min)
│   │   │   ├── requestId.js     X-Request-ID propagation
│   │   │   └── errorHandler.js  Global error handler
│   │   ├── routes/
│   │   │   ├── payments.js      Payment endpoints + validation
│   │   │   └── health.js        Kubernetes liveness/readiness
│   │   └── services/
│   │       └── paymentsService.js  Upstream proxy + circuit breaker
│   ├── tests/gateway.test.js    Jest tests
│   ├── k8s/deployment.yaml
│   ├── Dockerfile
│   └── package.json
│
├── data-processing-service/     ← Python 3.12 / Flask — Reconciliation & Analytics
│   ├── app/
│   │   ├── __init__.py          Flask application factory
│   │   ├── config/
│   │   │   ├── settings.py      Multi-environment configuration
│   │   │   ├── database.py      SQLAlchemy + Flask-Migrate
│   │   │   └── logging.py       Structlog JSON logging
│   │   ├── models/
│   │   │   └── reconciliation.py  ReconciliationRecord, ReconciliationRun
│   │   ├── routes/
│   │   │   ├── reconciliation.py  Reconciliation trigger + query endpoints
│   │   │   ├── reports.py         Analytics and summary endpoints
│   │   │   └── health.py          Kubernetes probes
│   │   ├── services/
│   │   │   └── reconciliation_service.py  Core reconciliation logic (pandas)
│   │   └── utils/
│   │       └── kafka_consumer.py   Payment event consumer (background thread)
│   ├── tests/test_reconciliation_service.py
│   ├── k8s/deployment.yaml      Deployment + CronJob (daily reconciliation)
│   ├── Dockerfile
│   ├── wsgi.py
│   ├── gunicorn.conf.py
│   ├── requirements.txt
│   └── pytest.ini
│
├── k8s-shared/
│   └── namespace-and-ingress.yaml  Namespace, ResourceQuota, Ingress, NetworkPolicy, RBAC
│
├── observability/
│   └── prometheus.yml           Prometheus scrape config
│
└── docker-compose.yml           Full local development stack
```

---

## Architecture at a Glance

```
Internet → [AWS WAF] → [External ALB] → [gateway-service :3000]
                                               │
                           ┌───────────────────┤
                           │                   │
                    [payments-service :8080]   │
                           │                   │
                    [PostgreSQL :5432]    [Kafka :9092]
                                               │
                                    [data-processing-service :5000]
                                               │
                                    [PostgreSQL :5433 (reporting)]
                                    [S3 (reconciliation reports)]
```

---

## Service Responsibilities

### 1. `payments-service` (Java / Spring Boot)
- Accepts payment creation requests
- Validates, persists, and publishes payment events to Kafka
- Manages payment lifecycle (PENDING → PROCESSING → COMPLETED/FAILED)
- Exposes an internal status-update endpoint for the clearing sub-system
- Scheduled retry job for failed payments (every 5 minutes)

### 2. `gateway-service` (Node.js / Express)
- Single entry point for all external clients
- JWT validation and RBAC enforcement (one-time, before forwarding)
- Input validation and request sanitisation
- Rate limiting (100 req/IP/min)
- Circuit breaker to `payments-service` (Opossum library)
- Forwards `X-Request-ID`, `X-User-ID`, `X-User-Roles` to upstream
- Prometheus metrics and Grafana dashboard integration

### 3. `data-processing-service` (Python / Flask)
- Consumes `payment-events` Kafka topic in a background thread
- Runs daily batch reconciliation against clearing network settlement files
- Downloads clearing files from S3, joins with internal data using pandas
- Classifies each payment as MATCHED / UNMATCHED / EXCEPTION
- Uploads reconciliation reports back to S3 (for Finance audit)
- REST API for triggering runs and querying results
- Kubernetes CronJob triggers the daily run at 06:00 UTC

---

## Local Development

### Prerequisites
- Docker Desktop 4.x+
- Java 17 (for running payments-service outside Docker)
- Node.js 20 (for running gateway-service outside Docker)
- Python 3.12 (for running data-processing-service outside Docker)

### Quick Start (Full Stack via Docker Compose)

```bash
# Clone and start everything
git clone https://github.com/your-org/global-payments-api.git
cd global-payments-api/microservices

# Start all services + infrastructure
docker-compose up -d

# Check all services are healthy
docker-compose ps

# Follow logs
docker-compose logs -f

# Access
# Gateway:            http://localhost:3000
# Payments Service:   http://localhost:8080/swagger-ui.html
# Data Processing:    http://localhost:5000/health
# SonarQube:          http://localhost:9000  (admin/admin)
# Grafana:            http://localhost:3001  (admin/admin)
# Prometheus:         http://localhost:9090
```

### Run Payments Service Locally (Hot Reload)

```bash
cd payments-service
./mvnw spring-boot:run -Dspring-boot.run.profiles=local
```

### Run Gateway Service Locally (Hot Reload)

```bash
cd gateway-service
cp .env.example .env
npm install
npm run dev
```

### Run Data Processing Service Locally

```bash
cd data-processing-service
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
export FLASK_ENV=development
export DATABASE_URL=postgresql://reporting_user:localpassword@localhost:5433/payments_reporting
flask run --port=5000
```

---

## Running Tests

### payments-service (requires Docker for Testcontainers)
```bash
cd payments-service
./mvnw verify
# Coverage report: target/site/jacoco/index.html
```

### gateway-service
```bash
cd gateway-service
npm test
# Coverage report: coverage/index.html
```

### data-processing-service
```bash
cd data-processing-service
source venv/bin/activate
pytest
# Coverage report: htmlcov/index.html
```

---

## Creating a Payment (API Example)

```bash
# 1. Get a test token (in production, this comes from your Identity Provider)
TOKEN="<your-jwt-token>"

# 2. Create a payment via the gateway
curl -X POST http://localhost:3000/api/v1/payments \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "senderAccountId":   "GB29NWBK60161331926819",
    "receiverAccountId": "GB82WEST12345698765432",
    "receiverBankCode":  "BARCGB22",
    "amount":            "250.00",
    "currency":          "GBP",
    "paymentType":       "DOMESTIC",
    "description":       "Test payment"
  }'

# 3. Get payment by reference
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/payments/ref/PAY-20240315-000001-AB12

# 4. Trigger a reconciliation run
curl -X POST http://localhost:5000/api/v1/reconciliation/run \
  -H "Content-Type: application/json" \
  -d '{"date": "2024-03-15"}'
```

---

## Security Notes

| Concern | Implementation |
|---------|---------------|
| **No hardcoded secrets** | All secrets via AWS Secrets Manager → K8s Secrets Store CSI |
| **JWT authentication** | Validated at gateway; downstream services trust `X-User-*` headers |
| **Non-root containers** | All Dockerfiles run as UID 1001 |
| **Read-only filesystem** | `readOnlyRootFilesystem: true` in K8s securityContext |
| **Network policies** | Default deny-all; only declared inter-service routes allowed |
| **RBAC** | Developers: read-only in prod; no `exec` access |
| **Pod Security Standards** | `restricted` profile enforced at namespace level |
| **Image scanning** | Trivy blocks CRITICAL/HIGH CVEs before image is pushed to ECR |

---

## Key Design Decisions

1. **Amounts in minor units** — `payments-service` stores amounts as `BIGINT` (pence/cents), never `DECIMAL` or `FLOAT`. Floating-point arithmetic on money is a compliance failure.
2. **Idempotency** — Every payment creation accepts an optional `Idempotency-Key`. Duplicate keys return the original result without creating a second payment.
3. **Optimistic locking** — The `Payment` entity has a `@Version` field. Concurrent updates are detected and rejected cleanly rather than silently overwriting.
4. **Circuit breaker** — The gateway's Opossum circuit breaker prevents cascading failures from propagating to clients when `payments-service` is degraded.
5. **Graceful shutdown** — All three services handle `SIGTERM` with a drain period (`preStop` hook + `terminationGracePeriodSeconds`) to allow in-flight requests to complete before the pod exits.
6. **Separation of databases** — `data-processing-service` has its own reporting database. It never queries the `payments-service` database directly — all data flows via Kafka events or the REST API.

---

*Global Payments API — DevOps Interview Toolkit | Stack: Java · Node.js · Python · EKS · Kafka · PostgreSQL · Terraform*
