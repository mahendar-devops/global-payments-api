# infra/modules/rds/outputs.tf

output "cluster_endpoint" {
  description = "Writer endpoint — use for INSERT/UPDATE/DELETE connections"
  value       = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint — use for SELECT/read-only connections"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "database_name" {
  description = "Name of the initial database"
  value       = aws_rds_cluster.main.database_name
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding master credentials"
  value       = aws_rds_cluster.main.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "RDS security group ID (add to EKS worker node egress rules)"
  value       = aws_security_group.rds.id
}

output "kms_key_arn" {
  description = "KMS key ARN used for RDS encryption"
  value       = aws_kms_key.rds.arn
}

output "port" {
  description = "Database port (PostgreSQL: 5432)"
  value       = aws_rds_cluster.main.port
}
