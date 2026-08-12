output "nodeclass_name" {
  description = "Name of the GPU Auto Mode NodeClass."
  value       = kubernetes_manifest.gpu_nodeclass.manifest.metadata.name
}

output "on_demand_nodepool_name" {
  description = "Name of the baseline On-Demand GPU NodePool."
  value       = kubernetes_manifest.gpu_on_demand_nodepool.manifest.metadata.name
}

output "spot_nodepool_name" {
  description = "Name of the elastic Spot GPU NodePool."
  value       = kubernetes_manifest.gpu_spot_nodepool.manifest.metadata.name
}