output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = module.s3.bucket_arn
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table"
  value       = module.dynamodb.table_arn
}

output "sns_topic_arn" {
  description = "The ARN of the SNS topic"
  value       = module.sqs_sns.sns_topic_arn
}

output "sqs_queue_url" {
  description = "The URL of the primary SQS queue"
  value       = module.sqs_sns.sqs_queue_url
}

output "sqs_queue_arn" {
  description = "The ARN of the primary SQS queue"
  value       = module.sqs_sns.sqs_queue_arn
}

output "sqs_dlq_url" {
  description = "The URL of the Dead-Letter SQS queue"
  value       = module.sqs_sns.sqs_dlq_url
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = module.lambda.lambda_function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = module.lambda.lambda_function_arn
}

output "lambda_event_source_mapping_uuid" {
  description = "The event source mapping UUID connecting SQS to Lambda"
  value       = module.lambda.event_source_mapping_uuid
}
