# EKS control plane security group (protects cluster API endpoint)
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.name_prefix}-eks-cluster-sg-${var.environment}"
  description = "Security group for EKS control plane."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                     = "${var.name_prefix}-eks-cluster-sg-${var.environment}"
    "karpenter.sh/discovery" = var.cluster_name
  })
}

# Allow inbound HTTPS API traffic from VPC (node groups and admins)
resource "aws_vpc_security_group_ingress_rule" "eks_api_from_vpc" {
  security_group_id = aws_security_group.eks_cluster_sg.id
  description       = "Allow Kubernetes API access from inside VPC."
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

# Allow all outbound traffic for cluster operations (ECR pull, DNS, etc.)
resource "aws_vpc_security_group_egress_rule" "eks_all_egress" {
  security_group_id = aws_security_group.eks_cluster_sg.id
  description       = "Allow all outbound traffic from EKS control plane SG."
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
