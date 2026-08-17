output "keda_release_name" {
  description = "Helm release name for KEDA."
  value       = helm_release.keda.name
}