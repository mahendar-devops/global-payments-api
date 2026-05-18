# infra/environments/prod/variables.tf

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "s3_reports_bucket_name" {
  description = "S3 bucket name for reconciliation reports"
  type        = string
}

variable "jwt_secret_arn" {
  description = "Secrets Manager ARN for the JWT signing secret"
  type        = string
  sensitive   = true
  # Value injected via TF_VAR_jwt_secret_arn in the Jenkins pipeline
  # NEVER set this in terraform.tfvars
}
