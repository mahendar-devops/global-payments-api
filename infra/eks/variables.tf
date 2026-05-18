# infra/eks/variables.tf

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "m5.xlarge"
}

variable "node_min_size" {
  description = "Minimum worker node count"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum worker node count (for Cluster Autoscaler)"
  type        = number
  default     = 10
}

variable "node_desired_size" {
  description = "Desired worker node count"
  type        = number
  default     = 3
}

variable "s3_reports_bucket_name" {
  description = "S3 bucket name for reconciliation reports"
  type        = string
}

variable "jwt_secret_arn" {
  description = "ARN of the JWT secret in Secrets Manager"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
