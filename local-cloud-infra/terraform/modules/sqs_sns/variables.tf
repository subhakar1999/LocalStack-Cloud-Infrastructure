variable "topic_name" {
  description = "Name of the SNS topic"
  type        = string
}

variable "queue_name" {
  description = "Name of the primary SQS queue"
  type        = string
}

variable "dlq_name" {
  description = "Name of the dead-letter SQS queue"
  type        = string
}

variable "max_receive_count" {
  description = "Number of times a message is delivered before being sent to the DLQ"
  type        = number
  default     = 5
}

variable "message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message"
  type        = number
  default     = 86400 # 1 day
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
