# Cluster identity outputs for downstream modules and kubeconfig
output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.cluster.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.cluster.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint."
  value       = aws_eks_cluster.cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane."
  value       = aws_security_group.eks_cluster_sg.id
}

# OIDC URL for pod identity and add-on integrations
output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA integrations."
  value       = try(aws_eks_cluster.cluster.identity[0].oidc[0].issuer, null)
}

output "cluster_oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA integrations."
  value       = aws_iam_openid_connect_provider.cluster_oidc.arn
}

output "node_role_name" {
  description = "IAM role name used by EKS Auto Mode nodes."
  value       = aws_iam_role.eks_node_role.name
}

output "cluster_primary_security_group_id" {
  description = "EKS-created primary cluster security group ID."
  value       = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the EKS API server."
  value       = aws_eks_cluster.cluster.certificate_authority[0].data
  sensitive   = true
}