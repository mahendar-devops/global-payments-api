# infra/environments/prod/main.tf
#
# Production environment Terraform entry point.
#
# Usage in Jenkins pipeline:
#   cd infra/environments/prod
#   terraform init \
#     -backend-config="bucket=payments-cluster-prod-tfstate" \
#     -backend-config="key=prod/terraform.tfstate" \
#     -backend-config="dynamodb_table=terraform-state-lock"
#   terraform plan -var-file="terraform.tfvars" -out=tfplan.binary
#   terraform apply tfplan.binary
#
# NOTE: The -var-file flag loads non-sensitive config. Sensitive values
# (JWT secret ARN, etc.) are set via TF_VAR_* environment variables
# injected by the Jenkins credentials store — never in .tfvars.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    region  = "eu-west-2"
    encrypt = true
    # bucket, key, dynamodb_table supplied via -backend-config in pipeline
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Environment = "prod"
      ManagedBy   = "Terraform"
      Project     = "GlobalPaymentsAPI"
    }
  }
}

module "platform" {
  source = "../../eks"

  environment    = "prod"
  aws_region     = "eu-west-2"
  cluster_name   = var.cluster_name
  cluster_version = var.cluster_version

  # Network
  vpc_cidr = var.vpc_cidr

  # Compute — production sizing
  node_instance_type = "m5.xlarge"
  node_min_size      = 3
  node_max_size      = 15
  node_desired_size  = 3

  # Storage
  s3_reports_bucket_name = var.s3_reports_bucket_name

  # Secrets (value passed via TF_VAR_jwt_secret_arn env var in Jenkins)
  jwt_secret_arn = var.jwt_secret_arn

  tags = {
    CostCentre  = "PAYMENTS-INFRA-PROD"
    Owner       = "payments-devops@globalpayments.com"
  }
}

# ── Outputs (inherit from module) ────────────────────────────────
output "cluster_name"             { value = module.platform.cluster_name }
output "kubectl_config_command"   { value = module.platform.kubectl_config_command }
output "payments_service_role_arn" { value = module.platform.payments_service_role_arn }
output "ecr_payments_service_url" { value = module.platform.ecr_payments_service_url }
output "rds_payments_secret_arn"  { value = module.platform.rds_payments_secret_arn }
