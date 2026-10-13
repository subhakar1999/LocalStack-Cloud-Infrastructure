module "s3" {
  source = "./modules/s3"

  bucket_name = var.s3_bucket_name
  environment = var.environment
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name   = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  environment  = var.environment
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

module "sqs_sns" {
  source = "./modules/sqs_sns"

  topic_name  = var.sns_topic_name
  queue_name  = var.sqs_queue_name
  dlq_name    = var.sqs_dlq_name
  environment = var.environment
  aws_region  = var.aws_region
  account_id  = var.localstack_account_id
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

module "lambda" {
  source = "./modules/lambda"

  function_name       = var.lambda_function_name
  account_id          = var.localstack_account_id
  dynamodb_table_name = module.dynamodb.table_name
  # Deterministic LocalStack ARNs keep IAM policy JSON known at plan time.
  # Explicit module dependencies below preserve provisioning order.
  dynamodb_table_arn = "arn:aws:dynamodb:${var.aws_region}:${var.localstack_account_id}:table/${var.dynamodb_table_name}"
  sqs_queue_arn      = "arn:aws:sqs:${var.aws_region}:${var.localstack_account_id}:${var.sqs_queue_name}"
  environment        = var.environment
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [
    module.dynamodb,
    module.sqs_sns
  ]
}
