# infra/modules/iam/main.tf
#
# IRSA (IAM Roles for Service Accounts) — the banking standard for
# pod-level AWS permissions. No static credentials, no shared keys.
#
# Each microservice gets its own IAM Role with only the permissions
# it specifically needs (Principle of Least Privilege).
#
# How IRSA works:
#   1. EKS OIDC provider federates pod identity to AWS IAM
#   2. Kubernetes ServiceAccount is annotated with the IAM Role ARN
#   3. When pod starts, AWS SDK auto-fetches temporary credentials
#   4. Credentials are scoped to exactly the actions in the role policy

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# ── Helper: OIDC assume-role policy (reused by all service roles) ─

locals {
  oidc_url = replace(var.oidc_provider_url, "https://", "")
}

# ══════════════════════════════════════════════════════════════════
# payments-service IAM Role
# Permissions: ECR (pull), Secrets Manager (read own secrets only)
# ══════════════════════════════════════════════════════════════════
resource "aws_iam_role" "payments_service" {
  name        = "${var.cluster_name}-payments-service-role"
  description = "IRSA role for payments-service pods"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:${var.namespace}:payments-service-sa"
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "payments_service" {
  name = "${var.cluster_name}-payments-service-policy"
  role = aws_iam_role.payments_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"    # ecr:GetAuthorizationToken requires *
      },
      {
        Sid    = "SecretsManagerOwnSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Only this service's secrets — not data-processing or gateway secrets
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:prod/payments-service/*",
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:prod/payments/jwt-secret*"
        ]
      },
      {
        Sid    = "KMSDecryptForSecrets"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "arn:aws:kms:${var.aws_region}:${var.aws_account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ══════════════════════════════════════════════════════════════════
# gateway-service IAM Role
# Permissions: ECR (pull), Secrets Manager (JWT secret only)
# Note: Gateway does NOT talk to DB — it proxies to payments-service
# ══════════════════════════════════════════════════════════════════
resource "aws_iam_role" "gateway_service" {
  name        = "${var.cluster_name}-gateway-service-role"
  description = "IRSA role for gateway-service pods"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:${var.namespace}:gateway-service-sa"
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "gateway_service" {
  name = "${var.cluster_name}-gateway-service-policy"
  role = aws_iam_role.gateway_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "JWTSecretRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Gateway only needs the JWT secret — nothing else
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:prod/payments/jwt-secret*"
        ]
      }
    ]
  })
}

# ══════════════════════════════════════════════════════════════════
# data-processing-service IAM Role
# Permissions: ECR (pull), S3 (reports bucket), Secrets Manager (DB)
# ══════════════════════════════════════════════════════════════════
resource "aws_iam_role" "data_processing_service" {
  name        = "${var.cluster_name}-data-processing-role"
  description = "IRSA role for data-processing-service pods"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:${var.namespace}:data-processing-sa"
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "data_processing_service" {
  name = "${var.cluster_name}-data-processing-policy"
  role = aws_iam_role.data_processing_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ReportsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_reports_bucket_arn,
          "${var.s3_reports_bucket_arn}/*"
        ]
      },
      {
        Sid    = "OwnSecretsRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:prod/data-processing-service/*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "arn:aws:kms:${var.aws_region}:${var.aws_account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "secretsmanager.${var.aws_region}.amazonaws.com",
              "s3.${var.aws_region}.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# ══════════════════════════════════════════════════════════════════
# Jenkins Agent IAM Role
# Permissions: ECR push, EKS describe, S3 state bucket
# ══════════════════════════════════════════════════════════════════
resource "aws_iam_role" "jenkins_agent" {
  name        = "${var.cluster_name}-jenkins-agent-role"
  description = "IRSA role for Jenkins agent pods (CI/CD)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:jenkins:jenkins-agent-sa"
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "jenkins_agent" {
  name = "${var.cluster_name}-jenkins-agent-policy"
  role = aws_iam_role.jenkins_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Sid    = "EKSDescribe"
        Effect = "Allow"
        Action = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.cluster_name}"
      },
      {
        Sid    = "TerraformStateS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.cluster_name}-tfstate*",
          "arn:aws:s3:::${var.cluster_name}-tfstate*/*"
        ]
      },
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/terraform-state-lock"
      }
    ]
  })
}

# ── Outputs ───────────────────────────────────────────────────────
output "payments_service_role_arn" {
  value = aws_iam_role.payments_service.arn
}

output "gateway_service_role_arn" {
  value = aws_iam_role.gateway_service.arn
}

output "data_processing_service_role_arn" {
  value = aws_iam_role.data_processing_service.arn
}

output "jenkins_agent_role_arn" {
  value = aws_iam_role.jenkins_agent.arn
}
