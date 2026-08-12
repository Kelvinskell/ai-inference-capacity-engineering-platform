# Module toggle and release identity.
variable "enabled" {
  description = "Whether to install kube-prometheus-stack."
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name for kube-prometheus-stack."
  type        = string
  default     = "kube-prometheus-stack"
}

# Namespace and chart source configuration.
variable "namespace" {
  description = "Namespace where kube-prometheus-stack is installed."
  type        = string
  default     = "monitoring"
}

variable "repository" {
  description = "Helm repository URL for kube-prometheus-stack."
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "chart" {
  description = "Helm chart name for the observability stack."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "chart_version" {
  description = "Helm chart version for kube-prometheus-stack."
  type        = string
}

# Prometheus data retention and storage settings.
variable "prometheus_retention" {
  description = "Prometheus TSDB retention period."
  type        = string
  default     = "10d"
}

variable "prometheus_storage_class" {
  description = "StorageClass name for Prometheus PVC; empty uses cluster default."
  type        = string
  default     = ""
}

variable "prometheus_storage_size" {
  description = "Requested persistent volume size for Prometheus data."
  type        = string
  default     = "50Gi"
}

# Helm operation timeout settings.
variable "helm_timeout_seconds" {
  description = "Timeout for Helm install/upgrade operations in seconds."
  type        = number
  default     = 900
}

variable "enable_dcgm_exporter" {
  description = "Enable Nvidia DCGM Exporter"
  type        = string
}

variable "dcgm_exporter_chart_version" {
  description = "Pinned DCGM exporter Helm chart version."
  type        = string
}