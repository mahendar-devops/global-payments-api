# ─────────────────────────────────────────────────────────────────
# Makefile — Global Payments API Developer Shortcuts
#
# Usage:
#   make help              Show all targets
#   make build             Build all three service Docker images
#   make test              Run tests for all services
#   make up                Start full stack via docker-compose
#   make down              Stop and remove all containers
#   make tf-plan ENV=prod  Terraform plan for a given environment
#   make tf-apply ENV=prod Terraform apply (with confirmation)
#   make lint              Lint all services
#   make clean             Remove build artifacts
# ─────────────────────────────────────────────────────────────────

.DEFAULT_GOAL := help
.PHONY: help build test lint up down logs clean \
        tf-init tf-plan tf-apply tf-destroy \
        build-payments build-gateway build-dataproc \
        test-payments test-gateway test-dataproc \
        k8s-deploy k8s-rollback k8s-status

# ── Configuration ─────────────────────────────────────────────────
ENV          ?= dev
AWS_REGION   ?= eu-west-2
ECR_REGISTRY ?= 123456789.dkr.ecr.$(AWS_REGION).amazonaws.com
IMAGE_TAG    ?= local-$(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
TF_DIR       := infra/environments/$(ENV)
CLUSTER_NAME ?= payments-cluster-$(ENV)

# Colours for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

# ── Help ──────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "$(GREEN)Global Payments API — Developer Makefile$(NC)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "$(YELLOW)Local Development:$(NC)"
	@echo "  make up                  Start full stack (docker-compose)"
	@echo "  make down                Stop all containers"
	@echo "  make logs                Follow all service logs"
	@echo "  make build               Build all Docker images"
	@echo "  make test                Run all tests with coverage"
	@echo "  make lint                Lint all services"
	@echo ""
	@echo "$(YELLOW)Individual Services:$(NC)"
	@echo "  make build-payments      Build payments-service image"
	@echo "  make build-gateway       Build gateway-service image"
	@echo "  make build-dataproc      Build data-processing-service image"
	@echo "  make test-payments       Run payments-service tests"
	@echo "  make test-gateway        Run gateway-service tests"
	@echo "  make test-dataproc       Run data-processing-service tests"
	@echo ""
	@echo "$(YELLOW)Terraform (specify ENV=dev|staging|prod):$(NC)"
	@echo "  make tf-init  ENV=dev    terraform init"
	@echo "  make tf-plan  ENV=dev    terraform plan"
	@echo "  make tf-apply ENV=dev    terraform apply (prompts for confirmation)"
	@echo "  make tf-destroy ENV=dev  terraform destroy (danger!)"
	@echo ""
	@echo "$(YELLOW)Kubernetes:$(NC)"
	@echo "  make k8s-deploy          Apply all K8s manifests to current context"
	@echo "  make k8s-rollback        Rollback all deployments"
	@echo "  make k8s-status          Show pod status in payments namespace"
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@echo "  make clean               Remove build artifacts"
	@echo "  make ecr-login           Authenticate Docker with ECR"
	@echo ""

# ── Docker Compose ────────────────────────────────────────────────
up:
	@echo "$(GREEN)Starting full stack...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)Services started. Access:$(NC)"
	@echo "  Gateway:          http://localhost:3000"
	@echo "  Payments Service: http://localhost:8080/swagger-ui.html"
	@echo "  Data Processing:  http://localhost:5000/health"
	@echo "  SonarQube:        http://localhost:9000  (admin/admin)"
	@echo "  Grafana:          http://localhost:3001  (admin/admin)"

down:
	@echo "$(YELLOW)Stopping all containers...$(NC)"
	docker-compose down

down-v:
	@echo "$(RED)Stopping containers and removing volumes...$(NC)"
	docker-compose down -v

logs:
	docker-compose logs -f

# ── Build ─────────────────────────────────────────────────────────
build: build-payments build-gateway build-dataproc
	@echo "$(GREEN)All images built with tag: $(IMAGE_TAG)$(NC)"

build-payments:
	@echo "$(GREEN)Building payments-service...$(NC)"
	docker build \
		--build-arg BUILD_VERSION=$(IMAGE_TAG) \
		--build-arg GIT_COMMIT=$(shell git rev-parse HEAD 2>/dev/null || echo "unknown") \
		--build-arg BUILD_TIMESTAMP=$(shell date -u +%Y-%m-%dT%H:%M:%SZ) \
		-t payments-service:$(IMAGE_TAG) \
		-t $(ECR_REGISTRY)/payments-service:$(IMAGE_TAG) \
		payments-service/

build-gateway:
	@echo "$(GREEN)Building gateway-service...$(NC)"
	docker build \
		--build-arg BUILD_VERSION=$(IMAGE_TAG) \
		-t gateway-service:$(IMAGE_TAG) \
		-t $(ECR_REGISTRY)/gateway-service:$(IMAGE_TAG) \
		gateway-service/

build-dataproc:
	@echo "$(GREEN)Building data-processing-service...$(NC)"
	docker build \
		--build-arg BUILD_VERSION=$(IMAGE_TAG) \
		-t data-processing-service:$(IMAGE_TAG) \
		-t $(ECR_REGISTRY)/data-processing-service:$(IMAGE_TAG) \
		data-processing-service/

# ── Test ──────────────────────────────────────────────────────────
test: test-payments test-gateway test-dataproc
	@echo "$(GREEN)All tests complete.$(NC)"

test-payments:
	@echo "$(GREEN)Running payments-service tests (requires Docker for Testcontainers)...$(NC)"
	cd payments-service && ./mvnw verify -B
	@echo "$(GREEN)Coverage report: payments-service/target/site/jacoco/index.html$(NC)"

test-gateway:
	@echo "$(GREEN)Running gateway-service tests...$(NC)"
	cd gateway-service && npm ci && npm test
	@echo "$(GREEN)Coverage report: gateway-service/coverage/index.html$(NC)"

test-dataproc:
	@echo "$(GREEN)Running data-processing-service tests...$(NC)"
	cd data-processing-service && \
		python -m venv .venv && \
		. .venv/bin/activate && \
		pip install -r requirements.txt -q && \
		pytest
	@echo "$(GREEN)Coverage report: data-processing-service/htmlcov/index.html$(NC)"

# ── Lint ──────────────────────────────────────────────────────────
lint: lint-gateway lint-terraform
	@echo "$(GREEN)Linting complete.$(NC)"

lint-gateway:
	@echo "$(GREEN)Linting gateway-service...$(NC)"
	cd gateway-service && npm run lint

lint-terraform:
	@echo "$(GREEN)Checking Terraform formatting...$(NC)"
	terraform fmt -check -recursive infra/
	@echo "$(GREEN)Validating Terraform configs...$(NC)"
	@for env in dev prod; do \
		echo "Validating infra/environments/$$env..."; \
		cd infra/environments/$$env && \
		terraform init -backend=false -input=false > /dev/null 2>&1 && \
		terraform validate && \
		cd ../../..; \
	done

# ── Terraform ─────────────────────────────────────────────────────
tf-init:
	@echo "$(GREEN)Initialising Terraform for $(ENV)...$(NC)"
	cd $(TF_DIR) && terraform init \
		-backend-config="bucket=$(CLUSTER_NAME)-tfstate" \
		-backend-config="key=$(ENV)/terraform.tfstate" \
		-backend-config="dynamodb_table=terraform-state-lock"

tf-plan: tf-init
	@echo "$(GREEN)Planning Terraform changes for $(ENV)...$(NC)"
	cd $(TF_DIR) && terraform plan \
		-var-file="terraform.tfvars" \
		-out=tfplan.binary
	@echo "$(YELLOW)Review the plan above before applying.$(NC)"

tf-apply:
	@echo "$(RED)Applying Terraform changes to $(ENV)...$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && \
		[ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1)
	cd $(TF_DIR) && terraform apply tfplan.binary

tf-fmt:
	terraform fmt -recursive infra/

tf-destroy:
	@echo "$(RED)WARNING: This will DESTROY all infrastructure in $(ENV)$(NC)"
	@read -p "Type the environment name to confirm ($(ENV)): " confirm && \
		[ "$$confirm" = "$(ENV)" ] || (echo "Aborted." && exit 1)
	cd $(TF_DIR) && terraform destroy -var-file="terraform.tfvars"

# ── Kubernetes ────────────────────────────────────────────────────
k8s-deploy:
	@echo "$(GREEN)Applying Kubernetes manifests...$(NC)"
	kubectl apply -f k8s-shared/
	kubectl apply -f payments-service/k8s/
	kubectl apply -f gateway-service/k8s/
	kubectl apply -f data-processing-service/k8s/
	kubectl rollout status deployment/payments-service     -n payments --timeout=5m
	kubectl rollout status deployment/gateway-service      -n payments --timeout=5m
	kubectl rollout status deployment/data-processing-service -n payments --timeout=5m
	@echo "$(GREEN)All deployments healthy.$(NC)"

k8s-rollback:
	@echo "$(YELLOW)Rolling back all deployments...$(NC)"
	kubectl rollout undo deployment/payments-service     -n payments
	kubectl rollout undo deployment/gateway-service      -n payments
	kubectl rollout undo deployment/data-processing-service -n payments

k8s-status:
	@echo "$(GREEN)Pod status in payments namespace:$(NC)"
	kubectl get pods -n payments -o wide
	@echo ""
	@echo "$(GREEN)HPA status:$(NC)"
	kubectl get hpa -n payments
	@echo ""
	@echo "$(GREEN)Recent events:$(NC)"
	kubectl get events -n payments --sort-by='.lastTimestamp' | tail -20

# ── ECR ───────────────────────────────────────────────────────────
ecr-login:
	@echo "$(GREEN)Authenticating with ECR...$(NC)"
	aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin $(ECR_REGISTRY)

ecr-push: ecr-login build
	@echo "$(GREEN)Pushing images to ECR...$(NC)"
	docker push $(ECR_REGISTRY)/payments-service:$(IMAGE_TAG)
	docker push $(ECR_REGISTRY)/gateway-service:$(IMAGE_TAG)
	docker push $(ECR_REGISTRY)/data-processing-service:$(IMAGE_TAG)

# ── Security Scans (run locally before pushing) ───────────────────
trivy-scan: build
	@echo "$(GREEN)Running Trivy scans...$(NC)"
	trivy image --severity CRITICAL,HIGH payments-service:$(IMAGE_TAG)
	trivy image --severity CRITICAL,HIGH gateway-service:$(IMAGE_TAG)
	trivy image --severity CRITICAL,HIGH data-processing-service:$(IMAGE_TAG)

# ── Clean ─────────────────────────────────────────────────────────
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	cd payments-service && ./mvnw clean -q 2>/dev/null || true
	rm -rf gateway-service/node_modules gateway-service/coverage
	rm -rf data-processing-service/.venv data-processing-service/__pycache__
	rm -rf data-processing-service/htmlcov data-processing-service/.pytest_cache
	find . -name "tfplan.binary" -delete
	find . -name "*.tfplan" -delete
	@echo "$(GREEN)Clean complete.$(NC)"
