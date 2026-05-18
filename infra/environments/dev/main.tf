# infra/environments/dev/main.tf
#
# Development environment — cost-optimised for developer testing.
# Key differences from prod:
#   - Single NAT Gateway (saves ~$100/month vs 3 NAT GWs)
#   - Smaller EC2 instance types
#   - Single RDS instances (no reader replicas)
#   - Shorter backup retention (7 days)
#   - No deletion protection (easy teardown)
#   - Fewer replicas per service

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    region  = "eu-west-2"
    encrypt = true
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "Terraform"
      Project     = "GlobalPaymentsAPI"
    }
  }
}

module "platform" {
  source = "../../eks"

  environment    = "dev"
  aws_region     = "eu-west-2"
  cluster_name   = var.cluster_name
  cluster_version = var.cluster_version

  vpc_cidr = "10.1.0.0/16"    # Different CIDR to avoid overlap with prod VPC

  # Dev sizing — cheaper instance types
  node_instance_type = "t3.medium"
  node_min_size      = 1
  node_max_size      = 4
  node_desired_size  = 2

  s3_reports_bucket_name = var.s3_reports_bucket_name
  jwt_secret_arn         = var.jwt_secret_arn

  tags = {
    CostCentre  = "PAYMENTS-INFRA-DEV"
    AutoShutdown = "true"    # Tag used by Lambda to auto-stop dev resources at night
  }
}

output "cluster_name"           { value = module.platform.cluster_name }
output "kubectl_config_command" { value = module.platform.kubectl_config_command }
