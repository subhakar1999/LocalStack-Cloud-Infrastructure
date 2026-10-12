output "bucket_id" {
  description = "The name / ID of the S3 bucket"
  value       = aws_s3_bucket.bucket.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.bucket.arn
}

output "bucket_name" {
  description = "The bucket domain/name"
  value       = aws_s3_bucket.bucket.bucket
}
