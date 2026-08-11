# EKS control plane (managed Kubernetes)
resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = var.cluster_log_types

  # Control plane networking: private subnets, security group, endpoint access
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = local.endpoint_private_access
    endpoint_public_access  = local.endpoint_public_access
  }

  # Select the EKS authentication backend (API, API_AND_CONFIG_MAP, or CONFIG_MAP).
  access_config {
    authentication_mode = var.authentication_mode
  }

  # EKS Auto Mode configuration
  compute_config = {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.eks_node_role.arn
  }
  # Network config
  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }
  # Storage config
  storage_config {
    block_storage {
      enabled = true
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_node_minimal,
    aws_iam_role_policy_attachment.eks_node_ecr
  ]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks-${var.environment}"
  })
}

# Create access entry
resource "aws_eks_access_entry" "principals" {
  for_each      = local.normalized_access_principal_arns
  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = each.value
  type          = "STANDARD"

  depends_on = [
    aws_eks_cluster.cluster
  ]
}

# Grant cluster-admin policy to each configured principal at cluster scope.
resource "aws_eks_access_policy_association" "cluster_admin" {
  for_each      = local.normalized_access_principal_arns
  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.principals
  ]
}