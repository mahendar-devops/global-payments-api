# infra/environments/dev/variables.tf

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "s3_reports_bucket_name" {
  description = "S3 bucket name for reconciliation reports (dev)"
  type        = string
}

variable "jwt_secret_arn" {
  description = "Secrets Manager ARN for the JWT signing secret"
  type        = string
  sensitive   = true
  # Injected via TF_VAR_jwt_secret_arn in Jenkins pipeline
}
