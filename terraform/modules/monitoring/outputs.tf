# Expose release metadata for environment-level outputs.
output "release_name" {
  description = "Helm release name for kube-prometheus-stack."
  value       = try(helm_release.kube_prometheus_stack[0].name, null)
}

output "namespace" {
  description = "Namespace where kube-prometheus-stack is installed."
  value       = var.namespace
}