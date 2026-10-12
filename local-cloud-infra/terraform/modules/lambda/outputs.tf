output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.function.arn
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.function.function_name
}

output "lambda_role_arn" {
  description = "The ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "event_source_mapping_uuid" {
  description = "The UUID of the SQS to Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.sqs_event_source.uuid
}
