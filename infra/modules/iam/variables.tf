# infra/modules/iam/variables.tf

variable "cluster_name" {
  description = "EKS cluster name (used to scope IAM policies)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (from the EKS module output)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https://)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (for constructing resource ARNs)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "s3_reports_bucket_arn" {
  description = "ARN of the S3 bucket for reconciliation reports"
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry URL (account.dkr.ecr.region.amazonaws.com)"
  type        = string
}

variable "rds_secret_arns" {
  description = "Map of service name to Secrets Manager ARN for DB credentials"
  type        = map(string)
  default     = {}
}

variable "jwt_secret_arn" {
  description = "ARN of the JWT secret in Secrets Manager"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where service accounts live"
  type        = string
  default     = "payments"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
