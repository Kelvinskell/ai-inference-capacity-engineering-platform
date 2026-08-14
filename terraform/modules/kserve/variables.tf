variable "helm_timeout_seconds" {
  description = "Timeout for Helm operations in seconds."
  type        = number
  default     = 900
}

variable "cert_manager_namespace" {
  description = "Namespace for cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_release_name" {
  description = "Helm release name for cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_repository" {
  description = "Helm repository URL for cert-manager."
  type        = string
  default     = "https://charts.jetstack.io"
}

variable "cert_manager_chart" {
  description = "Helm chart name for cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_chart_version" {
  description = "Pinned cert-manager chart version."
  type        = string
  default     = "v1.21.0"
}

variable "istio_namespace" {
  description = "Namespace for Istio."
  type        = string
  default     = "istio-system"
}

variable "istio_repository" {
  description = "Helm repository URL for Istio."
  type        = string
  default     = "https://istio-release.storage.googleapis.com/charts"
}

variable "istio_chart_version" {
  description = "Pinned Istio chart version."
  type        = string
  default     = "1.30.3"
}

variable "istio_base_release_name" {
  description = "Helm release name for Istio base."
  type        = string
  default     = "istio-base"
}

variable "istiod_release_name" {
  description = "Helm release name for Istio control plane."
  type        = string
  default     = "istiod"
}

variable "istio_ingressgateway_release_name" {
  description = "Helm release name for Istio ingress gateway."
  type        = string
  default     = "istio-ingressgateway"
}

variable "knative_serving_version" {
  description = "Pinned Knative Serving release tag."
  type        = string
  default     = "knative-v1.22.1"
}

variable "knative_net_istio_version" {
  description = "Pinned Knative net-istio release tag."
  type        = string
  default     = "knative-v1.22.1"
}

variable "knative_ingress_class" {
  description = "Knative ingress class."
  type        = string
  default     = "istio.ingress.networking.knative.dev"
}

variable "kserve_version" {
  description = "Pinned KServe release tag."
  type        = string
  default     = "v0.19.0"
}