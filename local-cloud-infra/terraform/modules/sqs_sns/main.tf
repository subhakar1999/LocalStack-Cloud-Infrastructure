locals {
  topic_arn = "arn:aws:sns:${var.aws_region}:${var.account_id}:${var.topic_name}"
  queue_arn = "arn:aws:sqs:${var.aws_region}:${var.account_id}:${var.queue_name}"
  dlq_arn   = "arn:aws:sqs:${var.aws_region}:${var.account_id}:${var.dlq_name}"
}

resource "aws_sns_topic" "topic" {
  name = var.topic_name

  tags = merge(
    var.tags,
    {
      Name        = var.topic_name
      Environment = var.environment
    }
  )

  lifecycle {
    postcondition {
      condition     = alltrue([for key in ["Project", "Environment", "Name"] : try(length(trimspace(self.tags[key])) > 0, false)])
      error_message = "SNS-001: Require Project, Environment and Name tags."
    }
  }
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

  lifecycle {
    postcondition {
      condition     = alltrue([for key in ["Project", "Environment", "Name"] : try(length(trimspace(self.tags[key])) > 0, false)]) && self.message_retention_seconds == 1209600
      error_message = "SQS-001: Require tags and 14-day DLQ retention."
    }
  }
}

resource "aws_sqs_queue" "primary" {
  name                      = var.queue_name
  message_retention_seconds = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = local.dlq_arn
    maxReceiveCount     = var.max_receive_count
  })

  depends_on = [aws_sqs_queue.dlq]

  tags = merge(
    var.tags,
    {
      Name        = var.queue_name
      Environment = var.environment
    }
  )

  lifecycle {
    postcondition {
      condition     = alltrue([for key in ["Project", "Environment", "Name"] : try(length(trimspace(self.tags[key])) > 0, false)]) && self.message_retention_seconds >= 86400 && self.message_retention_seconds <= aws_sqs_queue.dlq.message_retention_seconds && var.max_receive_count >= 1 && var.max_receive_count <= 10
      error_message = "SQS-002: Require tags, 1-14 day retention and 1-10 receive attempts."
    }
  }
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
        Resource = local.queue_arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = local.topic_arn
          }
        }
      }
    ]
  })

  depends_on = [aws_sns_topic.topic]

  lifecycle {
    postcondition {
      condition     = try(alltrue([for s in jsondecode(self.policy).Statement : s.Effect == "Allow" && s.Principal.Service == "sns.amazonaws.com" && s.Action == "sqs:SendMessage" && s.Resource == aws_sqs_queue.primary.arn && s.Condition.ArnEquals["aws:SourceArn"] == aws_sns_topic.topic.arn]), false)
      error_message = "SQS-003: Only this SNS topic may publish to the queue."
    }
  }
}

resource "aws_sns_topic_subscription" "subscription" {
  topic_arn            = local.topic_arn
  protocol             = "sqs"
  endpoint             = local.queue_arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.allow_sns]

  lifecycle {
    postcondition {
      condition     = self.protocol == "sqs" && self.raw_message_delivery
      error_message = "SNS-002: Require SQS protocol and raw delivery."
    }
  }
}
