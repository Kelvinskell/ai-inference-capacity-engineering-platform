output "nodeclass_name" {
  description = "Name of the GPU Auto Mode NodeClass."
  value       = kubectl_manifest.gpu_nodeclass.name
}

output "on_demand_nodepool_name" {
  description = "Name of the baseline On-Demand GPU NodePool."
  value       = kubectl_manifest.gpu_on_demand_nodepool.name
}

output "spot_nodepool_name" {
  description = "Name of the elastic Spot GPU NodePool."
  value       = kubectl_manifest.gpu_spot_nodepool.name
}