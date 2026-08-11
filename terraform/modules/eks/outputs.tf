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
