mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  governance_account_id = "111111111111"
  target_ou_ids         = ["ou-abcd-12345678"]
  target_regions        = ["us-east-1", "eu-west-1"]
}

run "automatic_multi_account_governance" {
  command = plan
  assert {
    condition     = aws_cloudformation_stack_set.governance.permission_model == "SERVICE_MANAGED" && aws_cloudformation_stack_set.governance.auto_deployment[0].enabled
    error_message = "Member accounts and newly joining accounts must receive governance."
  }
  assert {
    condition     = aws_cloudformation_stack_instances.members.regions == toset(["us-east-1", "eu-west-1"]) && aws_cloudformation_stack_instances.members.deployment_targets[0].organizational_unit_ids == toset(["ou-abcd-12345678"])
    error_message = "Deploy into every selected OU and Region."
  }
  assert {
    condition     = aws_cloudformation_stack_set.governance.parameters["AutomaticRemediation"] == "true"
    error_message = "Versioning must be repaired automatically by default."
  }
}

run "detection_only_rollout" {
  command = plan
  variables { automatic_remediation = false }
  assert {
    condition     = aws_cloudformation_stack_set.governance.parameters["AutomaticRemediation"] == "false"
    error_message = "Detection-only mode must disable automatic resource changes."
  }
}

run "delegated_administrator" {
  command = plan
  variables { call_as = "DELEGATED_ADMIN" }
  assert {
    condition     = aws_cloudformation_stack_set.governance.call_as == "DELEGATED_ADMIN" && aws_cloudformation_stack_instances.members.call_as == "DELEGATED_ADMIN"
    error_message = "Both StackSet operations must use the selected administrator mode."
  }
}

run "reject_empty_scope" {
  command = plan
  variables { target_ou_ids = [] }
  expect_failures = [var.target_ou_ids]
}
