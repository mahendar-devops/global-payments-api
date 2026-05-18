# infra/eks/main.tf
#
# Root module — orchestrates all sub-modules to build the full
# Global Payments API platform infrastructure on AWS.
#
# Module composition:
#   vpc     → Networking foundation (subnets, NAT GWs, VPC endpoints)
#   eks     → EKS cluster + managed node groups + add-ons
#   rds     → Aurora PostgreSQL (payments + reporting databases)
#   ecr     → Container registries for all three services
#   iam     → IRSA roles (one per service + Jenkins)
#   helm    → AWS Load Balancer Controller, Cluster Autoscaler, Secrets CSI

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = "GlobalPaymentsAPI"
    ManagedBy   = "Terraform"
    CostCentre  = "PAYMENTS-INFRA"
  })
}

# ── VPC ──────────────────────────────────────────────────────────
module "vpc" {
  source = "../modules/vpc"

  name               = var.cluster_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  cluster_name       = var.cluster_name
  single_nat_gateway = var.environment == "dev"   # Save cost in dev

  tags = local.common_tags
}

# ── EKS Cluster ──────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Private API endpoint — Kubernetes API not publicly accessible
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  # OIDC for IRSA — enables pod-level IAM roles
  enable_irsa = true

  # Encrypt Kubernetes Secrets at rest with CMK
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # Managed Node Group
  eks_managed_node_groups = {
    payments_workers = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      capacity_type  = "ON_DEMAND"    # Never Spot for payment processing

      # Rolling node updates — at most 33% unavailable at once
      update_config = {
        max_unavailable_percentage = 33
      }

      labels = { role = "payments-worker" }

      tags = local.common_tags
    }
  }

  # EKS Managed Add-ons
  cluster_addons = {
    coredns                          = { most_recent = true }
    kube-proxy                       = { most_recent = true }
    vpc-cni                          = { most_recent = true }
    aws-ebs-csi-driver               = { most_recent = true }
    aws-secrets-store-csi-driver     = { most_recent = true }
  }

  tags = local.common_tags
}

# KMS key for EKS secret encryption
resource "aws_kms_key" "eks" {
  description             = "EKS Secrets encryption — ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.common_tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# ── RDS — Payments Database ───────────────────────────────────────
module "rds_payments" {
  source = "../modules/rds"

  name               = "${var.cluster_name}-payments"
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  database_name      = "payments"
  master_username    = "payments_admin"
  instance_class     = var.environment == "prod" ? "db.r6g.large" : "db.t4g.medium"
  instance_count     = var.environment == "prod" ? 2 : 1

  allowed_security_group_ids = [module.eks.node_security_group_id]

  backup_retention_days = var.environment == "prod" ? 35 : 7
  deletion_protection   = var.environment == "prod"

  tags = local.common_tags
}

# ── RDS — Reporting Database (data-processing-service) ───────────
module "rds_reporting" {
  source = "../modules/rds"

  name               = "${var.cluster_name}-reporting"
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  database_name      = "payments_reporting"
  master_username    = "reporting_admin"
  instance_class     = var.environment == "prod" ? "db.r6g.medium" : "db.t4g.medium"
  instance_count     = var.environment == "prod" ? 2 : 1

  allowed_security_group_ids = [module.eks.node_security_group_id]

  backup_retention_days = var.environment == "prod" ? 35 : 7
  deletion_protection   = var.environment == "prod"

  tags = local.common_tags
}

# ── ECR Repositories ─────────────────────────────────────────────
module "ecr" {
  source = "../modules/ecr"

  repository_names = [
    "payments-service",
    "gateway-service",
    "data-processing-service"
  ]
  environment          = var.environment
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  retention_count      = var.environment == "prod" ? 50 : 10

  tags = local.common_tags
}

# ── S3 Bucket for Reconciliation Reports ─────────────────────────
resource "aws_s3_bucket" "reports" {
  bucket = var.s3_reports_bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── IAM (IRSA Roles) ─────────────────────────────────────────────
module "iam" {
  source = "../modules/iam"

  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.cluster_oidc_issuer_url
  aws_account_id    = data.aws_caller_identity.current.account_id
  aws_region        = var.aws_region
  namespace         = "payments"

  s3_reports_bucket_arn = aws_s3_bucket.reports.arn
  jwt_secret_arn        = var.jwt_secret_arn
  ecr_registry          = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}

# ── Helm: AWS Load Balancer Controller ───────────────────────────
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1"
  namespace  = "kube-system"

  set { name = "clusterName";             value = var.cluster_name }
  set { name = "serviceAccount.create";   value = "true" }
  set { name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
        value = module.iam.jenkins_agent_role_arn }  # Reuse or create dedicated role

  depends_on = [module.eks]
}

# ── Helm: Cluster Autoscaler ─────────────────────────────────────
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.35.0"
  namespace  = "kube-system"

  set { name = "autoDiscovery.clusterName"; value = var.cluster_name }
  set { name = "awsRegion";                  value = var.aws_region }

  depends_on = [module.eks]
}
