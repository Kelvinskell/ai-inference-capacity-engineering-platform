locals {
  # Convert single mode input to two AWS endpoint flags
  endpoint_private_access = contains(["private", "both"], var.endpoint_access_mode)
  endpoint_public_access  = contains(["public", "both"], var.endpoint_access_mode)

  # Kubernetes cluster ownership tag for service discovery
  common_tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

locals {
  # Use a set so duplicate ARNs do not create duplicate for_each instances.
  normalized_access_principal_arns = toset(var.access_principal_arns)
}
