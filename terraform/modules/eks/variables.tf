# Core cluster identity and naming
variable "name_prefix" {
  description = "Prefix used for naming EKS resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "environment" {
  description = "Environment suffix used in resource names (for example: dev, stage)."
  type        = string
}

# Control plane version
variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
}

# Networking inputs from networking module
variable "vpc_id" {
  description = "VPC ID where EKS control plane networking is configured."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block used to scope Kubernetes API security group access."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by the EKS control plane ENIs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "private_subnet_ids must contain at least 2 subnet IDs."
  }
}

# Single-source-of-truth for endpoint access (prevents conflicting booleans)
variable "endpoint_access_mode" {
  description = "EKS API endpoint access mode: private, public, or both."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public", "both"], var.endpoint_access_mode)
    error_message = "endpoint_access_mode must be one of: private, public, both."
  }
}

# EKS authentication mode for control-plane API authentication.
variable "authentication_mode" {
  description = "EKS authentication mode: CONFIG_MAP, API_AND_CONFIG_MAP, or API."
  type        = string
  default     = "API"

  validation {
    condition     = contains(["CONFIG_MAP", "API_AND_CONFIG_MAP", "API"], var.authentication_mode)
    error_message = "authentication_mode must be one of: CONFIG_MAP, API_AND_CONFIG_MAP or API."
  }
}

# IAM principals that will receive access entries and policy associations.
variable "access_principal_arns" {
  description = "IAM principal ARNs to grant EKS cluster access via access entries."
  type        = list(string)
  default     = []
}

# Logging and tags
variable "cluster_log_types" {
  description = "Enabled EKS control plane log types."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "tags" {
  description = "Additional tags applied to all EKS resources."
  type        = map(string)
  default     = {}
}
