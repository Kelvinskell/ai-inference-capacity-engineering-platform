# S3 CSI driver for persistent volumes
# Mountpoint for Amazon S3 CSI driver
resource "aws_eks_addon" "s3_csi" {
  cluster_name             = aws_eks_cluster.cluster.name
  addon_name               = "aws-mountpoint-s3-csi-driver"
  service_account_role_arn = aws_iam_role.s3_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_iam_role_policy_attachment.s3_csi
  ]

  tags = local.common_tags
}