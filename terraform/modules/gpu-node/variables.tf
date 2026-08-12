variable "node_role_name" {
  description = "IAM role name used by EKS Auto Mode GPU nodes."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs available to GPU nodes."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group ID attached to GPU nodes."
  type        = string
}

variable "on_demand_instance_types" {
  description = "EC2 GPU instance types allowed in the On-Demand NodePool."
  type        = list(string)
  default     = ["g5.xlarge"]
}

variable "spot_instance_types" {
  description = "EC2 GPU instance types allowed in the Spot NodePool."
  type        = list(string)
  default = [
    "g5.xlarge",
    "g5.2xlarge"
  ]
}

variable "on_demand_gpu_limit" {
  description = "Maximum number of GPUs provisioned by the On-Demand NodePool."
  type        = number
  default     = 2
}

variable "spot_gpu_limit" {
  description = "Maximum number of GPUs provisioned by the Spot NodePool."
  type        = number
  default     = 4
}