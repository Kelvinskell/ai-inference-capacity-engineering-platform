output "bucket_name" {
  description = "Name of the model artifact bucket."
  value       = aws_s3_bucket.model_storage.id
}

output "bucket_arn" {
  description = "ARN of the model artifact bucket."
  value       = aws_s3_bucket.model_storage.arn
}

output "model_uploader_role_arn" {
  description = "IAM role ARN for the EKS Pod Identity model uploader association."
  value       = aws_iam_role.model_uploader.arn
}

output "model_uploader_role_name" {
  description = "IAM role name for the EKS Pod Identity model uploader association."
  value       = aws_iam_role.model_uploader.name
}