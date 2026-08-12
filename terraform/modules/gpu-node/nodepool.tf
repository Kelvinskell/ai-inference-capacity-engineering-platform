# Create On-demand NodePool
resource "kubectl_manifest" "gpu_on_demand_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = "gpu-on-demand"
    }

    spec = {
      weight = 10 # Lower weight, so spot takes priority

      template = {
        metadata = {
          labels = {
            "workload-type" = "ai-inference"
            "capacity-tier" = "baseline"
            "gpu"           = "true"
          }
        }

        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "gpu"
          }

          taints = [
            {
              key    = "nvidia.com/gpu"
              value  = "true"
              effect = "NoSchedule"
            }
          ]

          requirements = [
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.on_demand_instance_types
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            }
          ]
        }
      }

      limits = {
        "nvidia.com/gpu" = tostring(var.on_demand_gpu_limit)
      }

      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "15m"
      }
    }
  })

  depends_on = [
    kubectl_manifest.gpu_nodeclass
  ]
}

# Spot Nodepool
resource "kubectl_manifest" "gpu_spot_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = "gpu-spot"
    }

    spec = {
      weight = 100 # Higher priority than on-demand

      template = {
        metadata = {
          labels = {
            "workload-type" = "ai-inference"
            "capacity-tier" = "elastic"
            "gpu"           = "true"
          }
        }

        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "gpu"
          }

          taints = [
            {
              key    = "nvidia.com/gpu"
              value  = "true"
              effect = "NoSchedule"
            }
          ]

          requirements = [
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.spot_instance_types
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot"]
            }
          ]
        }
      }

      limits = {
        "nvidia.com/gpu" = tostring(var.spot_gpu_limit)
      }

      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "5m"
      }
    }
  })

  depends_on = [
    kubectl_manifest.gpu_nodeclass
  ]
}