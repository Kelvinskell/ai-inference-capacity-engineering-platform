output "kserve_version" {
  description = "Pinned KServe version."
  value       = var.kserve_version
}

output "knative_serving_version" {
  description = "Pinned Knative Serving version."
  value       = var.knative_serving_version
}

output "istio_chart_version" {
  description = "Pinned Istio chart version."
  value       = var.istio_chart_version
}

output "cert_manager_chart_version" {
  description = "Pinned cert-manager chart version."
  value       = var.cert_manager_chart_version
}