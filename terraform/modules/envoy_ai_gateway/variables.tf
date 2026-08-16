variable "enabled" {
  description = "Whether to install Envoy Gateway and Envoy AI Gateway."
  type        = bool
  default     = true
}

variable "oci_repository" {
  description = "OCI repository containing the Envoy Gateway Helm charts."
  type        = string
  default     = "oci://docker.io/envoyproxy"
}

variable "envoy_gateway_namespace" {
  description = "Namespace where Envoy Gateway is installed."
  type        = string
  default     = "envoy-gateway-system"
}

variable "envoy_gateway_release_name" {
  description = "Helm release name for Envoy Gateway."
  type        = string
  default     = "envoy-gateway"
}

variable "envoy_gateway_chart" {
  description = "Helm chart name for Envoy Gateway."
  type        = string
  default     = "gateway-helm"
}

variable "envoy_gateway_chart_version" {
  description = "Pinned Envoy Gateway Helm chart version compatible with Envoy AI Gateway."
  type        = string
  default     = "v1.8.3"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.envoy_gateway_chart_version))
    error_message = "envoy_gateway_chart_version must be a stable semantic version prefixed with v."
  }
}

variable "envoy_ai_gateway_namespace" {
  description = "Namespace where Envoy AI Gateway is installed."
  type        = string
  default     = "envoy-ai-gateway-system"
}

variable "envoy_ai_gateway_crds_release_name" {
  description = "Helm release name for Envoy AI Gateway CRDs."
  type        = string
  default     = "envoy-ai-gateway-crds"
}

variable "envoy_ai_gateway_crds_chart" {
  description = "Helm chart name for Envoy AI Gateway CRDs."
  type        = string
  default     = "ai-gateway-crds-helm"
}

variable "envoy_ai_gateway_release_name" {
  description = "Helm release name for Envoy AI Gateway."
  type        = string
  default     = "envoy-ai-gateway"
}

variable "envoy_ai_gateway_chart" {
  description = "Helm chart name for Envoy AI Gateway."
  type        = string
  default     = "ai-gateway-helm"
}

variable "envoy_ai_gateway_chart_version" {
  description = "Pinned Envoy AI Gateway Helm chart version."
  type        = string
  default     = "v1.0.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.envoy_ai_gateway_chart_version))
    error_message = "envoy_ai_gateway_chart_version must be a stable semantic version prefixed with v."
  }
}

variable "helm_timeout_seconds" {
  description = "Timeout for Helm install and upgrade operations in seconds."
  type        = number
  default     = 900
}