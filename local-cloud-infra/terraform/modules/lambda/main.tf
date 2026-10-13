data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/index.py"
  output_path = "${path.module}/dist/lambda_function.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.function_name}-role"
      Environment = var.environment
    }
  )

  lifecycle {
    postcondition {
      condition     = alltrue([for key in ["Project", "Environment", "Name"] : try(length(trimspace(self.tags[key])) > 0, false)]) && try(alltrue([for s in jsondecode(self.assume_role_policy).Statement : s.Effect == "Allow" && s.Action == "sts:AssumeRole" && s.Principal.Service == "lambda.amazonaws.com"]), false)
      error_message = "IAM-001: Require tags and Lambda-only trust."
    }
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.function_name}-policy"
  description = "IAM policy for Lambda to read from SQS, write to DynamoDB, and write CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/*"
        ]
      }
    ]
  })

  lifecycle {
    postcondition {
      condition     = try(alltrue([for s in jsondecode(self.policy).Statement : s.Effect == "Allow" && alltrue([for action in flatten([s.Action]) : contains(["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"], action)]) && alltrue([for arn in flatten([s.Resource]) : arn != "*"])]), false)
      error_message = "IAM-002: Require approved pipeline actions and resource ARNs."
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::${var.account_id}:policy/${aws_iam_policy.lambda_policy.name}"
}

resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  role             = "arn:aws:iam::${var.account_id}:role/${aws_iam_role.lambda_role.name}"
  handler          = "index.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = var.function_name
      Environment = var.environment
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attach
  ]

  lifecycle {
    postcondition {
      condition     = alltrue([for key in ["Project", "Environment", "Name"] : try(length(trimspace(self.tags[key])) > 0, false)]) && contains(["python3.11", "python3.12", "python3.13"], self.runtime) && self.timeout >= 1 && self.timeout <= 30 && self.memory_size >= 128 && self.memory_size <= 1024
      error_message = "LAMBDA-001: Require tags, approved Python runtime, timeout 1-30s and memory 128-1024 MB."
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_event_source" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.function.function_name
  batch_size       = 10
  enabled          = true

  lifecycle {
    postcondition {
      condition     = self.enabled && self.batch_size >= 1 && self.batch_size <= 10
      error_message = "LAMBDA-002: Require enabled processing and batch size 1-10."
    }
  }
}
