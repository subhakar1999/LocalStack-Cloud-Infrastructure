output "sns_topic_arn" {
  description = "The ARN of the SNS topic"
  value       = aws_sns_topic.topic.arn
}

output "sns_topic_name" {
  description = "The name of the SNS topic"
  value       = aws_sns_topic.topic.name
}

output "sqs_queue_url" {
  description = "The URL of the primary SQS queue"
  value       = aws_sqs_queue.primary.id
}

output "sqs_queue_arn" {
  description = "The ARN of the primary SQS queue"
  value       = aws_sqs_queue.primary.arn
}

output "sqs_queue_name" {
  description = "The name of the primary SQS queue"
  value       = aws_sqs_queue.primary.name
}

output "sqs_dlq_url" {
  description = "The URL of the Dead-Letter SQS queue"
  value       = aws_sqs_queue.dlq.id
}

output "sqs_dlq_arn" {
  description = "The ARN of the Dead-Letter SQS queue"
  value       = aws_sqs_queue.dlq.arn
}
