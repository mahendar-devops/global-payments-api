#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# infra/free-tier/bootstrap.sh
#
# Run this ONCE before "terraform init".
# Creates the S3 bucket and DynamoDB table that Terraform uses
# to store its state file. These cannot be created BY Terraform
# because Terraform needs them to exist first (chicken-and-egg).
#
# Usage: bash bootstrap.sh
# ─────────────────────────────────────────────────────────────────
set -e

# ── 1. Get your AWS Account ID automatically ──────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-2"
BUCKET_NAME="payments-tfstate-${ACCOUNT_ID}"

echo "================================================"
echo "  Global Payments API — Terraform Bootstrap"
echo "================================================"
echo "Account ID : $ACCOUNT_ID"
echo "Region     : $REGION"
echo "S3 Bucket  : $BUCKET_NAME"
echo ""

# ── 2. Check the bucket doesn't already exist ─────────────────────
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "✅ S3 bucket already exists — skipping creation"
else
  echo "Creating S3 bucket: $BUCKET_NAME"

  # Create bucket (eu-west-2 requires LocationConstraint)
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

  # Enable versioning (recover old state if something goes wrong)
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

  # Enable server-side encryption
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
      }]
    }'

  # Block all public access (state files contain sensitive details)
  aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "✅ S3 bucket created and configured"
fi

# ── 3. Create DynamoDB table for state locking ────────────────────
if aws dynamodb describe-table --table-name terraform-state-lock --region "$REGION" 2>/dev/null; then
  echo "✅ DynamoDB lock table already exists — skipping"
else
  echo "Creating DynamoDB lock table..."
  aws dynamodb create-table \
    --table-name terraform-state-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  # Wait for it to be active
  echo "Waiting for DynamoDB table to become active..."
  aws dynamodb wait table-exists --table-name terraform-state-lock --region "$REGION"
  echo "✅ DynamoDB lock table created"
fi

# ── 4. Update backend.hcl and terraform.tfvars with real values ───
echo ""
echo "Updating backend.hcl with your account ID..."
sed -i "s/YOUR_ACCOUNT_ID/${ACCOUNT_ID}/g" backend.hcl
sed -i "s/YOUR_ACCOUNT_ID/${ACCOUNT_ID}/g" terraform.tfvars

echo ""
echo "================================================"
echo "  Bootstrap COMPLETE"
echo "================================================"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Edit terraform.tfvars — replace 0.0.0.0 with your home IP:"
echo "   Your current IP: $(curl -s https://checkip.amazonaws.com)"
echo ""
echo "2. Run terraform init:"
echo "   terraform init -backend-config=backend.hcl"
echo ""
echo "3. Run terraform plan:"
echo "   terraform plan -var-file=terraform.tfvars"
echo ""
echo "4. If the plan looks correct (2 EC2, 1 VPC, security groups):"
echo "   terraform apply -var-file=terraform.tfvars"
echo "   Type: yes"
echo ""
echo "⏱️  Wait ~5 minutes after apply for bootstrap scripts to finish."
