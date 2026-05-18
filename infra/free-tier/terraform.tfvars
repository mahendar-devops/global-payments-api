# infra/free-tier/terraform.tfvars
#
# INSTRUCTIONS:
#   1. Find your home IP:  curl https://checkip.amazonaws.com
#   2. Replace 0.0.0.0 below with your IP (keep the /32 at the end)
#   3. Replace YOUR_ACCOUNT_ID with your 12-digit AWS account number
#      Run: aws sts get-caller-identity --query Account --output text

your_home_ip  = "0.0.0.0/32"          # ← REPLACE with your home IP
state_bucket  = "payments-tfstate-YOUR_ACCOUNT_ID"  # ← REPLACE
aws_region    = "eu-west-2"
key_name      = "payments-devops"      # Must match the key you imported
