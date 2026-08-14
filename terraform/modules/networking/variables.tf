variable "name_prefix" {
  description = "Prefix used for naming networking resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags."
  type        = string
}

variable "environment" {
  description = "Environment suffix used in resource names (for example: dev, stage)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones to use."
  type        = number

  validation {
    condition     = var.az_count >= 1
    error_message = "az_count must be at least 1."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. Must match az_count."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == var.az_count
    error_message = "public_subnet_cidrs length must equal az_count."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets. Must match az_count."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == var.az_count
    error_message = "private_subnet_cidrs length must equal az_count."
  }
}

variable "nat_gateway_mode" {
  description = "NAT gateway strategy: single (cost optimized) or ha (one per AZ)."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "ha"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be either 'single' or 'ha'."
  }
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
