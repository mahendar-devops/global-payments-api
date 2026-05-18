# infra/eks/outputs.tf

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA configuration"
  value       = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# ── ECR Outputs ───────────────────────────────────────────────────
output "ecr_payments_service_url" {
  description = "ECR URL for payments-service"
  value       = module.ecr.repository_urls["payments-service"]
}

output "ecr_gateway_service_url" {
  description = "ECR URL for gateway-service"
  value       = module.ecr.repository_urls["gateway-service"]
}

output "ecr_data_processing_service_url" {
  description = "ECR URL for data-processing-service"
  value       = module.ecr.repository_urls["data-processing-service"]
}

# ── RDS Outputs ───────────────────────────────────────────────────
output "rds_payments_writer_endpoint" {
  description = "Aurora writer endpoint for payments DB"
  value       = module.rds_payments.cluster_endpoint
  sensitive   = true
}

output "rds_reporting_writer_endpoint" {
  description = "Aurora writer endpoint for reporting DB"
  value       = module.rds_reporting.cluster_endpoint
  sensitive   = true
}

output "rds_payments_secret_arn" {
  description = "Secrets Manager ARN for payments DB credentials"
  value       = module.rds_payments.master_user_secret_arn
}

output "rds_reporting_secret_arn" {
  description = "Secrets Manager ARN for reporting DB credentials"
  value       = module.rds_reporting.master_user_secret_arn
}

# ── IAM Outputs ───────────────────────────────────────────────────
output "payments_service_role_arn" {
  description = "IAM Role ARN for payments-service (annotate K8s ServiceAccount)"
  value       = module.iam.payments_service_role_arn
}

output "gateway_service_role_arn" {
  description = "IAM Role ARN for gateway-service"
  value       = module.iam.gateway_service_role_arn
}

output "data_processing_service_role_arn" {
  description = "IAM Role ARN for data-processing-service"
  value       = module.iam.data_processing_service_role_arn
}

output "jenkins_agent_role_arn" {
  description = "IAM Role ARN for Jenkins CI/CD agents"
  value       = module.iam.jenkins_agent_role_arn
}

# ── S3 Outputs ────────────────────────────────────────────────────
output "s3_reports_bucket_name" {
  description = "S3 bucket name for reconciliation reports"
  value       = aws_s3_bucket.reports.bucket
}

# ── kubectl config update command ────────────────────────────────
output "kubectl_config_command" {
  description = "Run this to configure kubectl after cluster creation"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
