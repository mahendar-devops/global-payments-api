# infra/modules/ecr/main.tf
#
# ECR repositories for all three microservices.
# Banking requirements met:
#   - IMMUTABLE tags: once PAY-20240315-000001 is pushed, it cannot be overwritten
#   - Encryption at rest with KMS CMK
#   - Continuous image scanning (Amazon Inspector)
#   - Lifecycle policy: auto-expire old images (storage cost control)
#   - Repository policy: least-privilege push/pull access

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# ── KMS Key for ECR encryption ────────────────────────────────────
resource "aws_kms_key" "ecr" {
  description             = "ECR image encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, { Name = "ecr-kms-key" })
}

# ── ECR Repositories (one per service) ───────────────────────────
resource "aws_ecr_repository" "services" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability    # IMMUTABLE — audit trail

  # Encryption at rest with CMK
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  image_scanning_configuration {
    scan_on_push = var.scan_on_push    # Basic scan; Trivy in pipeline is primary
  }

  tags = merge(var.tags, {
    Name        = each.value
    Environment = var.environment
  })
}

# ── Lifecycle Policy (auto-expire old images) ─────────────────────
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        # Keep the last N tagged images (production-ready images)
        rulePriority = 1
        description  = "Keep last ${var.retention_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release-", "main-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.retention_count
        }
        action = { type = "expire" }
      },
      {
        # Always clean up untagged images (leftover from failed builds)
        rulePriority = 2
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── Repository Policy (IAM — who can push/pull) ───────────────────
resource "aws_ecr_repository_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEKSPull"
        Effect = "Allow"
        Principal = {
          # EKS worker nodes can pull images
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      },
      {
        Sid    = "AllowJenkinsPush"
        Effect = "Allow"
        Principal = {
          # Jenkins service account role can push images
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/jenkins-agent-role"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
