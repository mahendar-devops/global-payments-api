# infra/free-tier/backend.hcl
#
# Used with: terraform init -backend-config=backend.hcl
#
# Fill in YOUR_ACCOUNT_ID before running.
# Get it with: aws sts get-caller-identity --query Account --output text

bucket         = "payments-tfstate-YOUR_ACCOUNT_ID"
key            = "free-tier/terraform.tfstate"
region         = "eu-west-2"
dynamodb_table = "terraform-state-lock"
encrypt        = true
