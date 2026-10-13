package main

import rego.v1

# Evaluate the complete planned inventory, including unchanged resources.
# Pure deletions are excluded here; surviving buckets must retain protections.
resources := {r |
    some r in input.resource_changes
    r.mode == "managed"
    r.change.after != null
}

supported := {
    "aws_s3_bucket", "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_ownership_controls", "aws_s3_bucket_versioning",
    "aws_s3_bucket_server_side_encryption_configuration",
    "aws_dynamodb_table", "aws_sns_topic", "aws_sns_topic_subscription",
    "aws_sqs_queue", "aws_sqs_queue_policy", "aws_iam_role",
    "aws_iam_policy", "aws_iam_role_policy_attachment",
    "aws_lambda_function", "aws_lambda_event_source_mapping",
}

tagged_types := {
    "aws_s3_bucket", "aws_dynamodb_table", "aws_sns_topic",
    "aws_sqs_queue", "aws_iam_role", "aws_lambda_function",
}

environment := input.variables.environment.value
region := input.variables.aws_region.value
account := input.variables.localstack_account_id.value
function_name := input.variables.lambda_function_name.value
queue_arn := sprintf("arn:aws:sqs:%s:%s:%s", [region, account, input.variables.sqs_queue_name.value])
dlq_arn := sprintf("arn:aws:sqs:%s:%s:%s", [region, account, input.variables.sqs_dlq_name.value])
topic_arn := sprintf("arn:aws:sns:%s:%s:%s", [region, account, input.variables.sns_topic_name.value])
table_arn := sprintf("arn:aws:dynamodb:%s:%s:table/%s", [region, account, input.variables.dynamodb_table_name.value])
execution_policy_arn := sprintf("arn:aws:iam::%s:policy/%s-policy", [account, function_name])

valid_input if {
    startswith(input.format_version, "1.")
    is_array(input.resource_changes)
    is_string(environment)
    trim_space(environment) != ""
    is_string(region)
    regex.match("^[0-9]{12}$", account)
    count(resources) > 0
    object.get(input, "errored", false) == false
}

deny contains "INPUT-001: Expected a non-empty Terraform plan JSON with environment, region and LocalStack account variables." if {
    not valid_input
}

deny contains sprintf("COVERAGE-001: %s uses resource type %s without an approved policy.", [r.address, r.type]) if {
    some r in resources
    not r.type in supported
}

deny contains sprintf("INVENTORY-001: The stack is missing required resource type %s; partial/targeted or destroy plans are not deployable through this gate.", [kind]) if {
    some kind in supported
    not type_present(kind)
}
type_present(kind) if {
    some r in resources
    r.type == kind
}

valid_tags(r) if {
    tags := r.change.after.tags
    every key in ["Project", "Environment", "Name"] {
        is_string(tags[key])
        trim_space(tags[key]) != ""
    }
    tags.Environment == environment
}

deny contains sprintf("TAG-001: %s requires known non-empty Project, Environment and Name tags matching the deployment environment.", [r.address]) if {
    some r in resources
    r.type in tagged_types
    not valid_tags(r)
}

# One bucket per module is the supported layout for this repository. Requiring
# companions also detects removal of an entire protection resource.
bucket_protected(bucket, kind) if {
    siblings := {r | some r in resources; r.type == "aws_s3_bucket"; object.get(r, "module_address", "") == object.get(bucket, "module_address", "")}
    count(siblings) == 1
    some protection in resources
    protection.type == kind
    object.get(protection, "module_address", "") == object.get(bucket, "module_address", "")
    bucket_linked(bucket, protection)
}

bucket_linked(bucket, protection) if {
    protection.change.after.bucket == bucket.change.after.bucket
}

deny contains sprintf("S3-006: %s is missing an associated %s protection (one bucket per module required).", [r.address, kind]) if {
    some r in resources
    r.type == "aws_s3_bucket"
    some kind in ["aws_s3_bucket_public_access_block", "aws_s3_bucket_ownership_controls", "aws_s3_bucket_versioning", "aws_s3_bucket_server_side_encryption_configuration"]
    not bucket_protected(r, kind)
}

deny contains sprintf("RESOURCE-001: %s (%s) violates its policy or has unknown required security values.", [r.address, r.type]) if {
    some r in resources
    r.type in supported
    not compliant(r)
}

compliant(r) if {
    r.type == "aws_s3_bucket"
    environment == "local"
}
compliant(r) if {
    r.type == "aws_s3_bucket"
    r.change.after.force_destroy == false
}
compliant(r) if {
    r.type == "aws_s3_bucket_public_access_block"
    every key in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"] {
        r.change.after[key] == true
    }
}
compliant(r) if {
    r.type == "aws_s3_bucket_ownership_controls"
    r.change.after.rule[0].object_ownership == "BucketOwnerEnforced"
}
compliant(r) if {
    r.type == "aws_s3_bucket_versioning"
    r.change.after.versioning_configuration[0].status == "Enabled"
}
compliant(r) if {
    r.type == "aws_s3_bucket_server_side_encryption_configuration"
    rules := r.change.after.rule
    count(rules) > 0
    every rule in rules {
        rule.apply_server_side_encryption_by_default[0].sse_algorithm in {"AES256", "aws:kms"}
    }
}
compliant(r) if {
    r.type == "aws_dynamodb_table"
    r.change.after.billing_mode == "PAY_PER_REQUEST"
    recovery_allowed(r.change.after)
}
recovery_allowed(_) if { environment == "local" }
recovery_allowed(v) if { v.point_in_time_recovery[0].enabled == true }
compliant(r) if { r.type == "aws_sns_topic" }
compliant(r) if {
    r.type == "aws_sns_topic_subscription"
    r.change.after.protocol == "sqs"
    r.change.after.raw_message_delivery == true
    r.change.after.topic_arn == topic_arn
    r.change.after.endpoint == queue_arn
}
compliant(r) if {
    r.type == "aws_sqs_queue"
    r.change.after.tags.Type == "DLQ"
    r.change.after.name == input.variables.sqs_dlq_name.value
    r.change.after.message_retention_seconds == 1209600
}
compliant(r) if {
    r.type == "aws_sqs_queue"
    r.change.after.name == input.variables.sqs_queue_name.value
    retention := r.change.after.message_retention_seconds
    retention >= 86400
    retention <= 1209600
    policy := json.unmarshal(r.change.after.redrive_policy)
    policy.deadLetterTargetArn == dlq_arn
    policy.maxReceiveCount >= 1
    policy.maxReceiveCount <= 10
    some dlq in resources
    dlq.type == "aws_sqs_queue"
    dlq.change.after.name == input.variables.sqs_dlq_name.value
    retention <= dlq.change.after.message_retention_seconds
}
compliant(r) if {
    r.type == "aws_sqs_queue_policy"
    policy := json.unmarshal(r.change.after.policy)
    policy.Version == "2012-10-17"
    count(policy.Statement) > 0
    every s in policy.Statement {
        s.Effect == "Allow"
        s.Principal == {"Service": "sns.amazonaws.com"}
        as_array(s.Action) == ["sqs:SendMessage"]
        as_array(s.Resource) == [queue_arn]
        s.Condition.ArnEquals["aws:SourceArn"] == topic_arn
    }
}
as_array(value) := value if { is_array(value) }
as_array(value) := [value] if { is_string(value) }
compliant(r) if {
    r.type == "aws_iam_role"
    policy := json.unmarshal(r.change.after.assume_role_policy)
    policy.Version == "2012-10-17"
    count(policy.Statement) > 0
    every s in policy.Statement {
        s.Effect == "Allow"
        s.Principal == {"Service": "lambda.amazonaws.com"}
        as_array(s.Action) == ["sts:AssumeRole"]
    }
}
compliant(r) if {
    r.type == "aws_iam_policy"
    policy := json.unmarshal(r.change.after.policy)
    policy.Version == "2012-10-17"
    count(policy.Statement) > 0
    every s in policy.Statement {
        s.Effect == "Allow"
        actions := as_array(s.Action)
        arns := as_array(s.Resource)
        count(actions) > 0
        count(arns) > 0
        every action in actions {
            every arn in arns { approved_permission(action, arn) }
        }
    }
}
approved_permission(action, arn) if {
    action in {"sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"}
    arn == queue_arn
}
approved_permission(action, arn) if {
    action in {"dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"}
    arn in {table_arn, sprintf("%s/*", [table_arn])}
}
approved_permission(action, arn) if {
    action in {"logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"}
    # Existing LocalStack logging exception, explicitly scoped to local plans.
    environment == "local"
    arn == "arn:aws:logs:*:*:*"
}
approved_permission(action, arn) if {
    action in {"logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"}
    arn == sprintf("arn:aws:logs:%s:%s:log-group:/aws/lambda/%s:*", [region, account, function_name])
}
compliant(r) if {
    r.type == "aws_iam_role_policy_attachment"
    r.change.after.role == sprintf("%s-role", [function_name])
    attachment_scoped(r)
}
attachment_scoped(r) if { r.change.after.policy_arn == execution_policy_arn }
compliant(r) if {
    r.type == "aws_lambda_function"
    r.change.after.runtime in {"python3.11", "python3.12", "python3.13"}
    r.change.after.timeout >= 1
    r.change.after.timeout <= 30
    r.change.after.memory_size >= 128
    r.change.after.memory_size <= 1024
    r.change.after.role == sprintf("arn:aws:iam::%s:role/%s-role", [account, function_name])
}
compliant(r) if {
    r.type == "aws_lambda_event_source_mapping"
    r.change.after.enabled == true
    r.change.after.batch_size >= 1
    r.change.after.batch_size <= 10
    r.change.after.event_source_arn == queue_arn
    r.change.after.function_name == function_name
}
