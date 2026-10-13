variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "account_id" {
  description = "Emulated account ID used to make IAM references known in plans"
  type        = string
  default     = "000000000000"
}

variable "dynamodb_table_name" {
  description = "Name of target DynamoDB table"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of target DynamoDB table for IAM policy permission"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue used as event source"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "local"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
