# Pod identity assoc for model uploader
resource "aws_eks_pod_identity_association" "model_uploader" {
  cluster_name    = var.eks_cluster_name
  namespace       = "model-uploader"
  service_account = "model-uploader"
  role_arn        = aws_iam_role.model_uploader.arn
}