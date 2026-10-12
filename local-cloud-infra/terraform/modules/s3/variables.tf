variable "bucket_name" {
  description = "The name of the S3 bucket"
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
