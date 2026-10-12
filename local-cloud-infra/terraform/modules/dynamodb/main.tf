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
}
