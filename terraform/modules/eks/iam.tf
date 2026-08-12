# EKS cluster service role and trust policy
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.name_prefix}-eks-cluster-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks-cluster-role-${var.environment}"
  })
}

# Attach AWS managed EKS cluster policy
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Auto Mode Node Role
resource "aws_iam_role" "eks_node_role" {
  name = "${var.name_prefix}-eks-node-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_node_minimal" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# S3 CSI driver role.
# IAM role used by the Mountpoint for Amazon S3 CSI driver.
data "aws_iam_policy_document" "s3_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster_oidc.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:s3-csi-driver-sa"]
    }
  }
}

resource "aws_iam_role" "s3_csi" {
  name               = "${var.name_prefix}-s3-csi-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.s3_csi_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "s3_csi" {
  statement {
    sid       = "ListModelBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.model_bucket_arn]
  }

  statement {
    sid       = "ReadModelObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.model_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "s3_csi" {
  name   = "${var.name_prefix}-s3-csi-${var.environment}"
  policy = data.aws_iam_policy_document.s3_csi.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "s3_csi" {
  role       = aws_iam_role.s3_csi.name
  policy_arn = aws_iam_policy.s3_csi.arn
}