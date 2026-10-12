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
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

module "lambda" {
  source = "./modules/lambda"

  function_name       = var.lambda_function_name
  dynamodb_table_name = module.dynamodb.table_name
  dynamodb_table_arn  = module.dynamodb.table_arn
  sqs_queue_arn       = module.sqs_sns.sqs_queue_arn
  environment         = var.environment
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [
    module.dynamodb,
    module.sqs_sns
  ]
}
