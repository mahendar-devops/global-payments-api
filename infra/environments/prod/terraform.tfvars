# infra/environments/prod/terraform.tfvars
#
# Non-sensitive production configuration values.
# This file IS committed to Git — it contains NO secrets.
#
# Sensitive values (jwt_secret_arn, DB passwords) are injected by
# the Jenkins pipeline via TF_VAR_* environment variables sourced
# from the Jenkins Credentials Store.

cluster_name   = "payments-cluster-prod"
cluster_version = "1.29"
vpc_cidr       = "10.0.0.0/16"

s3_reports_bucket_name = "payments-reports-prod-123456789"
