output "vpc_id" {
  description = "VPC ID for the dev environment."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for the dev environment."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs for the dev environment."
  value       = module.networking.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs for the dev environment."
  value       = module.networking.nat_gateway_ids
}

# EKS cluster outputs
output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL."
  value       = module.eks.cluster_oidc_issuer_url
}

output "model_uploader_role_arn" {
  description = "IAM role ARN for the EKS Pod Identity model uploader association."
  value       = module.s3.model_uploader_role_arn
}

output "model_uploader_role_name" {
  description = "IAM role name for the EKS Pod Identity model uploader association."
  value       = module.s3.model_uploader_role_name
}