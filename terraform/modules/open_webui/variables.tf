variable "enabled" {
  description = "Whether to install Open WebUI."
  type        = bool
  default     = true
}

variable "open_webui_chart_version" {
  description = "Pinned Open WebUI Helm chart version."
  type        = string
  default     = "16.0.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.open_webui_chart_version))
    error_message = "open_webui_chart_version must be a stable semantic version."
  }
}

variable "open_webui_storage_class" {
  description = "StorageClass used by the Open WebUI PVC."
  type        = string
  default     = "auto-ebs-gp3"
}

variable "open_webui_storage_size" {
  description = "Storage requested by the Open WebUI PVC."
  type        = string
  default     = "5Gi"

  validation {
    condition     = can(regex("^[1-9][0-9]*(Ki|Mi|Gi|Ti|Pi|Ei)$", var.open_webui_storage_size))
    error_message = "open_webui_storage_size must be a valid Kubernetes quantity."
  }
}

variable "openai_base_api_url" {
  description = "OpenAI-compatible Envoy AI Gateway endpoint used by Open WebUI."
  type        = string
  default     = "http://envoy-ai-gateway.envoy-gateway-system.svc.cluster.local/v1"
}

variable "development_secret" {
  description = "Non-production key used for Open WebUI sessions and Envoy authentication."
  type        = string
  default     = "notforprod"
  sensitive   = true
}

variable "helm_timeout_seconds" {
  description = "Timeout for Helm install and upgrade operations in seconds."
  type        = number
  default     = 900
}
