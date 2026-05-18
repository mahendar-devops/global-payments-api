# infra/environments/dev/terraform.tfvars
# Non-sensitive dev configuration. Safe to commit.

cluster_name   = "payments-cluster-dev"
cluster_version = "1.29"

s3_reports_bucket_name = "payments-reports-dev-123456789"
