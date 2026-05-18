# infra/modules/iam/outputs.tf
# These outputs are referenced by the EKS root module (infra/eks/main.tf)
# to annotate Kubernetes ServiceAccounts with the correct IAM Role ARNs.

output "payments_service_role_arn" {
  description = "IAM Role ARN for payments-service IRSA"
  value       = aws_iam_role.payments_service.arn
}

output "gateway_service_role_arn" {
  description = "IAM Role ARN for gateway-service IRSA"
  value       = aws_iam_role.gateway_service.arn
}

output "data_processing_service_role_arn" {
  description = "IAM Role ARN for data-processing-service IRSA"
  value       = aws_iam_role.data_processing_service.arn
}

output "jenkins_agent_role_arn" {
  description = "IAM Role ARN for Jenkins CI/CD agent pods"
  value       = aws_iam_role.jenkins_agent.arn
}

output "payments_service_role_name" {
  description = "IAM Role name for payments-service (used in aws_iam_role_policy attachments)"
  value       = aws_iam_role.payments_service.name
}

output "jenkins_agent_role_name" {
  description = "IAM Role name for Jenkins agent"
  value       = aws_iam_role.jenkins_agent.name
}
