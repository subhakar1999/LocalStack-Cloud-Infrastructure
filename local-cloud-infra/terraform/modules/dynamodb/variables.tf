variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "billing_mode" {
  description = "Billing mode for DynamoDB table (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
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
