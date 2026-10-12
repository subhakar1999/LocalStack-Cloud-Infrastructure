resource "aws_sns_topic" "topic" {
  name = var.topic_name

  tags = merge(
    var.tags,
    {
      Name        = var.topic_name
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue" "dlq" {
  name                      = var.dlq_name
  message_retention_seconds = 1209600 # 14 days

  tags = merge(
    var.tags,
    {
      Name        = var.dlq_name
      Environment = var.environment
      Type        = "DLQ"
    }
  )
}

resource "aws_sqs_queue" "primary" {
  name                      = var.queue_name
  message_retention_seconds = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(
    var.tags,
    {
      Name        = var.queue_name
      Environment = var.environment
    }
  )
}

resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.primary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.queue_name}-policy"
    Statement = [
      {
        Sid    = "AllowSNSSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.primary.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.topic.arn
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "subscription" {
  topic_arn            = aws_sns_topic.topic.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.primary.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.allow_sns]
}
