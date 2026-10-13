# Terraform >= 1.7; mock AWS calls and only plan, never apply.
mock_provider "aws" {}

run "local_stack_allowed" {
  command = plan
}

run "non_local_requires_protection" {
  command = plan
  module {
    source = "./modules/s3"
  }
  variables {
    bucket_name = "policy-test-bucket"
    environment = "production"
    tags        = { Project = "policy-test" }
  }
  expect_failures = [aws_s3_bucket.bucket]
}

run "non_local_requires_recovery" {
  command = plan
  module {
    source = "./modules/dynamodb"
  }
  variables {
    table_name  = "policy-test-table"
    environment = "production"
    tags        = { Project = "policy-test" }
  }
  expect_failures = [aws_dynamodb_table.table]
}

run "missing_project_tag_rejected" {
  command = plan
  module {
    source = "./modules/s3"
  }
  variables {
    bucket_name = "policy-test-bucket"
    environment = "local"
    tags        = {}
  }
  expect_failures = [aws_s3_bucket.bucket]
}

run "short_retention_rejected" {
  command = plan
  module {
    source = "./modules/sqs_sns"
  }
  variables {
    topic_name                = "policy-test-topic"
    queue_name                = "policy-test-queue"
    dlq_name                  = "policy-test-dlq"
    message_retention_seconds = 60
    tags                      = { Project = "policy-test" }
  }
  expect_failures = [aws_sqs_queue.primary]
}

run "unbounded_retries_rejected" {
  command = plan
  module {
    source = "./modules/sqs_sns"
  }
  variables {
    topic_name        = "policy-test-topic"
    queue_name        = "policy-test-queue"
    dlq_name          = "policy-test-dlq"
    max_receive_count = 11
    tags              = { Project = "policy-test" }
  }
  expect_failures = [aws_sqs_queue.primary]
}
