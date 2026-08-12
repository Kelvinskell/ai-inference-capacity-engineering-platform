resource "kubernetes_manifest" "gpu_nodeclass" {
  manifest = {
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "NodeClass"

    metadata = {
      name = "gpu-nodeclass"
    }

    spec = {
      role = var.node_role_name

      subnetSelectorTerms = [
        for subnet_id in var.private_subnet_ids : {
          id = subnet_id
        }
      ]

      securityGroupSelectorTerms = [
        {
          id = var.node_security_group_id
        }
      ]

      snatPolicy             = "Random"
      networkPolicy          = "DefaultAllow"
      networkPolicyEventLogs = "Disabled"

      ephemeralStorage = {
        size       = "80Gi"
        iops       = 3000
        throughput = 125
      }
    }
  }
}

