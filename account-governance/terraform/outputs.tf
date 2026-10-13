output "stack_set_name" {
  value = aws_cloudformation_stack_set.governance.name
}

output "config_rule_name" {
  value = "${var.policy_prefix}-s3-versioning"
}

output "aggregator_name" {
  value = aws_config_configuration_aggregator.organization.name
}

output "deployed_targets" {
  description = "Discovered member account/Region deployments, including their StackSet status"
  value       = aws_cloudformation_stack_instances.members.stack_instance_summaries
}
