# infra/modules/vpc/outputs.tf

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (for EKS worker nodes)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (for NAT GWs and ALBs)"
  value       = aws_subnet.public[*].id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "private_route_table_ids" {
  description = "Private route table IDs (used for S3 VPC endpoint association)"
  value       = aws_route_table.private[*].id
}

output "s3_endpoint_id" {
  description = "VPC endpoint ID for S3"
  value       = aws_vpc_endpoint.s3.id
}
