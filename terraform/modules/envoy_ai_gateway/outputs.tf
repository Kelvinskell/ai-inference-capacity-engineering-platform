output "envoy_gateway_namespace" {
  description = "Namespace where Envoy Gateway is installed."
  value       = var.envoy_gateway_namespace
}

output "envoy_gateway_chart_version" {
  description = "Pinned Envoy Gateway Helm chart version."
  value       = var.envoy_gateway_chart_version
}

output "envoy_ai_gateway_namespace" {
  description = "Namespace where Envoy AI Gateway is installed."
  value       = var.envoy_ai_gateway_namespace
}

output "envoy_ai_gateway_chart_version" {
  description = "Pinned Envoy AI Gateway Helm chart version."
  value       = var.envoy_ai_gateway_chart_version
}