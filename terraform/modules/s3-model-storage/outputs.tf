output "bucket_name" {
  description = "Name of the model artifact bucket."
  value       = aws_s3_bucket.model_storage.id
}

output "bucket_arn" {
  description = "ARN of the model artifact bucket."
  value       = aws_s3_bucket.model_storage.arn
}