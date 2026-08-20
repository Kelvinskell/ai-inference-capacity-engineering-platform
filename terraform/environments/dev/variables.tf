variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID where infrastructure is provisioned."
  type        = string
}

variable "terraform_execution_role_name" {
  description = "IAM role name assumed by Terraform."
  type        = string
  default     = "ai-inference-terraform-role"
}

variable "environment" {
  description = "Environment name (dev, stage, etc.) used in resource naming."
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Base project prefix used for resource naming."
  type        = string
  default     = "ai-inference"
}

variable "cluster_name" {
  description = "EKS cluster name used for Kubernetes discovery tags."
  type        = string
  default     = "ai-inference-eks-dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR for this environment."
  type        = string
}

variable "az_count" {
  description = "Number of AZs to use."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count should be at least 2 for EKS environments."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs. Must match az_count."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs. Must match az_count."
  type        = list(string)
}

variable "nat_gateway_mode" {
  description = "NAT gateway mode for private subnet egress: single or ha."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "ha"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be either 'single' or 'ha'."
  }
}

variable "tags" {
  description = "Environment-wide default tags."
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Project     = "AI-Inference-Capacity-Engineering-Platform"
  }
}

# EKS control plane configuration
variable "kubernetes_version" {
  description = "Kubernetes version for EKS control plane."
  type        = string
  default     = "1.36"
}

variable "endpoint_access_mode" {
  description = "EKS API endpoint access mode: private, public, or both."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public", "both"], var.endpoint_access_mode)
    error_message = "endpoint_access_mode must be one of: private, public, both."
  }
}

# EKS authentication and API-based access bootstrap
variable "authentication_mode" {
  description = "EKS authentication mode for this environment."
  type        = string
  default     = "API"

  validation {
    condition     = contains(["CONFIG_MAP", "API_AND_CONFIG_MAP", "API"], var.authentication_mode)
    error_message = "authentication_mode must be one of: CONFIG_MAP, API_AND_CONFIG_MAP, API."
  }
}

# Principals that receive cluster-admin via EKS access entries
variable "access_principal_arns" {
  description = "IAM principal ARNs that should receive EKS cluster admin via access entries."
  type        = list(string)
  default     = []
}

variable "enable_monitoring" {
  description = "Enable kube-prometheus-stack installation."
  type        = bool
  default     = true
}

variable "monitoring_namespace" {
  description = "Namespace for kube-prometheus-stack."
  type        = string
  default     = "monitoring"
}

variable "kube_prometheus_stack_chart_version" {
  description = "Pinned kube-prometheus-stack chart version."
  type        = string
  default     = "87.17.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([-.].+)?$", var.kube_prometheus_stack_chart_version))
    error_message = "kube_prometheus_stack_chart_version must be a valid chart version (for example: 78.5.0)."
  }
}

variable "prometheus_retention" {
  description = "Prometheus retention period."
  type        = string
  default     = "10d"

  validation {
    condition     = can(regex("^[0-9]+(ms|s|m|h|d|w|y)$", var.prometheus_retention))
    error_message = "prometheus_retention must be a Prometheus duration (for example: 10d, 24h, 30m)."
  }
}

variable "prometheus_storage_class" {
  description = "StorageClass for Prometheus PVC. Empty means chart default."
  type        = string
  default     = "auto-ebs-gp3"
}

variable "prometheus_storage_size" {
  description = "Prometheus PVC size."
  type        = string
  default     = "50Gi"

  validation {
    condition     = can(regex("^[1-9][0-9]*(Ki|Mi|Gi|Ti|Pi|Ei)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a valid Kubernetes quantity (for example: 50Gi)."
  }
}

variable "enable_dcgm_exporter" {
  description = "Enable Nvidia DCGM Exporter"
  type        = bool
  default     = true
}

variable "dcgm_exporter_chart_version" {
  description = "Pinned DCGM exporter Helm chart version."
  type        = string
  default     = "4.8.3"
}

# KServe
variable "enable_kserve_module" {
  description = "Enable or disable kserve module"
  type        = bool
  default     = true
}

# Envoy AI Gateway
variable "enable_envoy_ai_gateway" {
  description = "Enable Envoy Gateway and Envoy AI Gateway installation."
  type        = bool
  default     = true
}

variable "envoy_gateway_chart_version" {
  description = "Pinned Envoy Gateway chart version compatible with Envoy AI Gateway."
  type        = string
  default     = "v1.8.3"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.envoy_gateway_chart_version))
    error_message = "envoy_gateway_chart_version must be a stable semantic version prefixed with v."
  }
}

variable "envoy_ai_gateway_chart_version" {
  description = "Pinned Envoy AI Gateway chart version."
  type        = string
  default     = "v1.0.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.envoy_ai_gateway_chart_version))
    error_message = "envoy_ai_gateway_chart_version must be a stable semantic version prefixed with v."
  }
}

# Open WebUI
variable "enable_open_webui" {
  description = "Enable Open WebUI installation."
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