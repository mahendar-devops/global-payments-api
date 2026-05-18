# infra/eks/backend.tf
#
# Remote State Configuration — S3 + DynamoDB locking.
#
# WHY THIS MATTERS (Interview answer):
#   In a team environment, multiple engineers may run Terraform simultaneously.
#   Without state locking, concurrent applies can corrupt the state file.
#   S3 stores the state (versioned, encrypted). DynamoDB provides locking
#   (atomic write — only one apply can hold the lock at a time).
#
# BOOTSTRAP:
#   The S3 bucket and DynamoDB table must be created ONCE manually (or
#   via a separate bootstrap Terraform config) before this can be used.
#
#   aws s3api create-bucket \
#     --bucket payments-cluster-prod-tfstate \
#     --region eu-west-2 \
#     --create-bucket-configuration LocationConstraint=eu-west-2
#
#   aws s3api put-bucket-versioning \
#     --bucket payments-cluster-prod-tfstate \
#     --versioning-configuration Status=Enabled
#
#   aws dynamodb create-table \
#     --table-name terraform-state-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region eu-west-2

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws        = { source = "hashicorp/aws",        version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes",  version = "~> 2.0" }
    helm       = { source = "hashicorp/helm",        version = "~> 2.0" }
    tls        = { source = "hashicorp/tls",         version = "~> 4.0" }
  }

  backend "s3" {
    # These values are supplied via -backend-config in the pipeline
    # or via environments/<env>/backend.hcl — never hardcoded here.
    # Example pipeline command:
    #   terraform init \
    #     -backend-config="bucket=payments-cluster-prod-tfstate" \
    #     -backend-config="key=eks/terraform.tfstate" \
    #     -backend-config="dynamodb_table=terraform-state-lock"

    region         = "eu-west-2"
    encrypt        = true       # AES-256 server-side encryption
    # kms_key_id is set via -backend-config in environments that use CMK
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "GlobalPaymentsAPI"
      Repository  = "global-payments-api/infra"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}
