locals {
  governance_template = file("${path.module}/../templates/s3-versioning.yaml")
}

resource "aws_cloudformation_stack_set" "governance" {
  name             = "${var.policy_prefix}-s3-versioning"
  description      = "Organization S3 versioning detection and remediation"
  permission_model = "SERVICE_MANAGED"
  call_as          = var.call_as
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.governance_template

  parameters = {
    PolicyPrefix         = var.policy_prefix
    AutomaticRemediation = tostring(var.automatic_remediation)
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = true
  }

  managed_execution {
    active = true
  }
}

# One operation handles all target Regions, avoiding concurrent StackSet updates
# from independent per-Region resources.
resource "aws_cloudformation_stack_instances" "members" {
  stack_set_name = aws_cloudformation_stack_set.governance.name
  call_as        = var.call_as
  regions        = var.target_regions

  deployment_targets {
    organizational_unit_ids = var.target_ou_ids
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 1
    region_concurrency_type = "SEQUENTIAL"
  }
}

data "aws_partition" "current" {}

resource "aws_iam_role" "aggregator" {
  name = "${var.policy_prefix}-config-aggregator"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "aggregator" {
  role       = aws_iam_role.aggregator.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "organization" {
  name = "${var.policy_prefix}-compliance"
  organization_aggregation_source {
    role_arn    = aws_iam_role.aggregator.arn
    all_regions = true
  }
  depends_on = [aws_iam_role_policy_attachment.aggregator]
}
