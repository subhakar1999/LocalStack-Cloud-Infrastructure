variable "aws_region" {
  description = "The target AWS region for LocalStack emulation"
  type        = string
  default     = "us-east-1"
}

variable "localstack_account_id" {
  description = "Emulated account ID used to build policy ARNs before resources exist"
  type        = string
  default     = "000000000000"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.localstack_account_id))
    error_message = "LocalStack account ID must contain exactly 12 digits."
  }
}

variable "aws_access_key" {
  description = "AWS access key mock credential for LocalStack"
  type        = string
  default     = "test"
}

variable "aws_secret_key" {
  description = "AWS secret key mock credential for LocalStack"
  type        = string
  default     = "test"
}

variable "localstack_endpoint" {
  description = "URL endpoint where LocalStack gateway is listening"
  type        = string
  default     = "http://localhost:4566"
}

variable "project_name" {
  description = "Name of the project used for naming and tagging"
  type        = string
  default     = "local-cloud-infra"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "local"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to create"
  type        = string
  default     = "local-assets-bucket"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
  default     = "local-events-table"
}

variable "sns_topic_name" {
  description = "Name of the SNS topic"
  type        = string
  default     = "local-events-topic"
}

variable "sqs_queue_name" {
  description = "Name of the primary SQS queue"
  type        = string
  default     = "local-events-queue"
}

variable "sqs_dlq_name" {
  description = "Name of the dead-letter queue"
  type        = string
  default     = "local-events-dlq"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "local-sqs-processor"
}
