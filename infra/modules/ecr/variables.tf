# infra/modules/ecr/variables.tf

variable "repository_names" {
  description = "List of ECR repository names to create (one per microservice)"
  type        = list(string)
  default     = ["payments-service", "gateway-service", "data-processing-service"]
}

variable "image_tag_mutability" {
  description = "IMMUTABLE enforces tag immutability — critical for prod audit trails"
  type        = string
  default     = "IMMUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Must be MUTABLE or IMMUTABLE"
  }
}

variable "scan_on_push" {
  description = "Enable ECR basic scanning on image push (Trivy in pipeline is primary)"
  type        = bool
  default     = true
}

variable "retention_count" {
  description = "Number of images to keep per repository (older images auto-deleted)"
  type        = number
  default     = 30
}

variable "allowed_account_ids" {
  description = "AWS account IDs allowed to pull images (e.g. prod account from dev ECR)"
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
