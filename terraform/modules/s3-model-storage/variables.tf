variable "bucket_name" {
  description = "Globally unique name for the model artifact bucket."
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket and all model objects."
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "The name of the eks cluster"
  type        = string
}

variable "tags" {
  description = "Tags applied to S3 resources."
  type        = map(string)
  default     = {}
}