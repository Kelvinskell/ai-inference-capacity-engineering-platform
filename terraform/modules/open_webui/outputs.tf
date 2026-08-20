output "open_webui_release_name" {
  description = "Open WebUI Helm release name."
  value       = try(helm_release.open_webui[0].name, null)
}