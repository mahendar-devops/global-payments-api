# infra/modules/rds/variables.tf

variable "name" {
  description = "Name prefix for RDS resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the RDS cluster will be placed"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to the RDS cluster (EKS worker SG)"
  type        = list(string)
}

variable "database_name" {
  description = "Initial database name to create"
  type        = string
  default     = "payments"
}

variable "master_username" {
  description = "Master username — value stored in Secrets Manager, not here"
  type        = string
  default     = "payments_admin"
}

variable "instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of Aurora instances (1 writer + N-1 readers)"
  type        = number
  default     = 2
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "backup_retention_days" {
  description = "Days to retain automated backups (7 minimum for compliance)"
  type        = number
  default     = 35
}

variable "deletion_protection" {
  description = "Enable deletion protection (always true in prod)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
