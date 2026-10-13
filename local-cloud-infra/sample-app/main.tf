terraform {
  required_version = ">= 1.5.0"
  required_providers {
    # LocalStack 3.8.1 does not implement the validation API used by >= 5.67.
    aws     = { source = "hashicorp/aws", version = "= 5.66.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    lambda   = "http://localhost:4566"
    iam      = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
    sfn      = "http://localhost:4566"
  }
  default_tags {
    tags = { Project = "sample-orders", Environment = "local", ManagedBy = "Terraform" }
  }
}
resource "aws_dynamodb_table" "orders" {
  name         = "sample-orders"
  billing_mode = "PAY_PER_REQUEST"
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
  tags = { Name = "sample-orders" }
}
resource "aws_iam_role" "lambda" {
  name               = "sample-orders-lambda-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }] })
}
resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.orders.arn },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:us-east-1:000000000000:log-group:/aws/lambda/sample-orders-*:*" }
  ] })
}
data "archive_file" "code" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/dist/sample.zip"
}
resource "aws_lambda_function" "task" {
  for_each         = toset(["validate", "calculate", "persist"])
  function_name    = "sample-orders-${each.key}"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.${each.key}"
  runtime          = "python3.11"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  timeout          = 30
  memory_size      = 128
  environment {
    variables = { ORDERS_TABLE = aws_dynamodb_table.orders.name }
  }
  tags       = { Name = "sample-orders-${each.key}" }
  depends_on = [aws_iam_role_policy.lambda]
}
resource "aws_iam_role" "workflow" {
  name               = "sample-orders-workflow-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "states.amazonaws.com" } }] })
}
resource "aws_iam_role_policy" "workflow" {
  role   = aws_iam_role.workflow.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = [for f in aws_lambda_function.task : f.arn] }] })
}
resource "aws_sfn_state_machine" "orders" {
  name     = "sample-order-processing"
  role_arn = aws_iam_role.workflow.arn
  type     = "STANDARD"
  definition = jsonencode({
    Comment = "Sample order application: validate, calculate, persist"
    StartAt = "ValidateOrder"
    States = {
      ValidateOrder = {
        Type  = "Task", Resource = aws_lambda_function.task["validate"].arn, Next = "CalculateTotal"
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "OrderFailed" }]
      }
      CalculateTotal = {
        Type  = "Task", Resource = aws_lambda_function.task["calculate"].arn, Next = "SaveOrder"
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "OrderFailed" }]
      }
      SaveOrder = {
        Type  = "Task", Resource = aws_lambda_function.task["persist"].arn, End = true
        Retry = [{ ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"], IntervalSeconds = 2, MaxAttempts = 3, BackoffRate = 2 }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "OrderFailed" }]
      }
      OrderFailed = { Type = "Fail", Error = "OrderProcessingFailed", Cause = "A Lambda task failed. Inspect execution history for details." }
    }
  })
  depends_on = [aws_iam_role_policy.workflow]
}
output "state_machine_arn" { value = aws_sfn_state_machine.orders.arn }
output "table_name" { value = aws_dynamodb_table.orders.name }
