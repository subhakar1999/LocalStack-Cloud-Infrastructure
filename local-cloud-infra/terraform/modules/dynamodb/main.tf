resource "aws_dynamodb_table" "table" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }

  tags = merge(
    var.tags,
    {
      Name        = var.table_name
      Environment = var.environment
    }
  )

  lifecycle {
    postcondition {
      condition     = alltrue([for key in ["Project", "Environment", "Name"] : try(length(trimspace(self.tags[key])) > 0, false)]) && self.billing_mode == "PAY_PER_REQUEST" && (var.environment == "local" || self.point_in_time_recovery[0].enabled)
      error_message = "DDB-001: Require tags, on-demand billing and non-local point-in-time recovery."
    }
  }
}
