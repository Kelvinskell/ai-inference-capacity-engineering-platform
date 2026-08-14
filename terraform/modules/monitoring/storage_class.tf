resource "kubernetes_storage_class_v1" "prometheus" {
  count = var.enabled ? 1 : 0

  metadata {
    name = "auto-ebs-gp3"
  }

  storage_provisioner    = "ebs.csi.eks.amazonaws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}