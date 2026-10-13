package main

import rego.v1

baseline := data.fixtures.valid

changed(name, patch) := object.union(baseline, {"resource_changes": changes}) if {
    changes := [replace_after(r, name, patch) | some r in baseline.resource_changes]
}
replace_after(r, name, patch) := object.union(object.remove(r, {"change"}), {"change": change}) if {
    r.name == name
    after := object.union(object.remove(r.change.after, object.keys(patch)), patch)
    change := object.union(object.remove(r.change, {"after"}), {"after": after})
}
replace_after(r, name, _) := r if { r.name != name }

rejected(plan) if {
    failures := deny with input as plan
    count(failures) > 0
}

test_compliant_local_plan if {
    failures := deny with input as baseline
    count(failures) == 0
}
test_invalid_input if { rejected({}) }
test_empty_inventory if { rejected(object.union(baseline, {"resource_changes": []})) }
test_failed_terraform_plan if { rejected(object.union(baseline, {"errored": true})) }
test_missing_project_tag if { rejected(changed("bucket", {"tags": {"Environment": "local", "Name": "assets"}})) }
test_blank_project_tag if { rejected(changed("bucket", {"tags": {"Environment": "local", "Name": "assets", "Project": " "}})) }
test_forged_local_environment if { rejected(changed("bucket", {"tags": {"Environment": "production", "Name": "assets", "Project": "test"}})) }
test_every_public_access_flag_required if {
    every key in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"] {
        rejected(changed("public_access", {key: false}))
    }
}
test_wrong_bucket_protection_target if { rejected(changed("public_access", {"bucket": "another-bucket"})) }
test_deleted_bucket_protection if {
    changes := [r | some r in baseline.resource_changes; r.name != "public_access"]
    rejected(object.union(baseline, {"resource_changes": changes}))
}
test_deletion_only_does_not_count_as_protection if {
    changes := [r | some r in changed("public_access", {}).resource_changes; r.name != "public_access"]
    original := [r | some r in baseline.resource_changes; r.name == "public_access"][0]
    deletion := object.union(original, {"change": {"actions": ["delete"], "after": null}})
    rejected(object.union(baseline, {"resource_changes": array.concat(changes, [deletion])}))
}
test_versioning_suspended if { rejected(changed("versioning", {"versioning_configuration": [{"status": "Suspended"}]})) }
test_acl_ownership if { rejected(changed("ownership", {"rule": [{"object_ownership": "ObjectWriter"}]})) }
test_no_encryption_rules if { rejected(changed("sse", {"rule": []})) }
test_unapproved_encryption if {
    rejected(changed("sse", {"rule": [{"apply_server_side_encryption_by_default": [{"sse_algorithm": "none"}]}]}))
}
test_provisioned_dynamodb if { rejected(changed("table", {"billing_mode": "PROVISIONED"})) }
test_non_local_storage_exceptions_rejected if {
    vars := object.union(baseline.variables, {"environment": {"value": "production"}})
    rejected(object.union(baseline, {"variables": vars}))
}
test_short_primary_retention if { rejected(changed("primary", {"message_retention_seconds": 60})) }
test_short_dlq_retention if { rejected(changed("dlq", {"message_retention_seconds": 86400})) }
test_unbounded_redrive if {
    rejected(changed("primary", {"redrive_policy": json.marshal({"deadLetterTargetArn": "arn:aws:sqs:us-east-1:000000000000:local-events-dlq", "maxReceiveCount": 100})}))
}
test_wrong_redrive_target if {
    rejected(changed("primary", {"redrive_policy": json.marshal({"deadLetterTargetArn": "arn:aws:sqs:us-east-1:000000000000:other-dlq", "maxReceiveCount": 5})}))
}
test_subscription_wrong_topic if { rejected(changed("subscription", {"topic_arn": "arn:aws:sns:us-east-1:000000000000:other-topic"})) }
test_raw_delivery_disabled if { rejected(changed("subscription", {"raw_message_delivery": false})) }
test_wildcard_queue_principal if {
    policy := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "sqs:SendMessage", "Resource": "*", "Principal": "*"}]}
    rejected(changed("allow_sns", {"policy": json.marshal(policy)}))
}
test_wildcard_iam_action if {
    policy := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]}
    rejected(changed("lambda_policy", {"policy": json.marshal(policy)}))
}
test_unrelated_iam_resource if {
    policy := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "dynamodb:PutItem", "Resource": "arn:aws:dynamodb:us-east-1:000000000000:table/unrelated"}]}
    rejected(changed("lambda_policy", {"policy": json.marshal(policy)}))
}
test_empty_iam_policy if { rejected(changed("lambda_policy", {"policy": "{\"Version\":\"2012-10-17\",\"Statement\":[]}"})) }
test_malformed_iam_policy if { rejected(changed("lambda_policy", {"policy": "not-json"})) }
test_unknown_iam_policy if { rejected(changed("lambda_policy", {"policy": null})) }
test_untrusted_service if {
    policy := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "sts:AssumeRole", "Principal": {"Service": "ec2.amazonaws.com"}}]}
    rejected(changed("lambda_role", {"assume_role_policy": json.marshal(policy)}))
}
test_unapproved_policy_attachment if { rejected(changed("lambda_policy_attach", {"policy_arn": "arn:aws:iam::000000000000:policy/AdministratorAccess"})) }
test_lambda_limits if {
    every patch in [{"timeout": 31}, {"memory_size": 2048}, {"runtime": "python2.7"}] {
        rejected(changed("function", patch))
    }
}
test_wrong_execution_role if { rejected(changed("function", {"role": "arn:aws:iam::000000000000:role/admin"})) }
test_disabled_event_source if { rejected(changed("sqs_event_source", {"enabled": false})) }
test_wrong_event_source if { rejected(changed("sqs_event_source", {"event_source_arn": "arn:aws:sqs:us-east-1:000000000000:unrelated"})) }
test_oversized_batch if { rejected(changed("sqs_event_source", {"batch_size": 100})) }
test_new_resource_type_requires_policy if {
    extra := {"address": "aws_security_group.unapproved", "mode": "managed", "type": "aws_security_group", "name": "unapproved", "change": {"actions": ["create"], "after": {}}}
    rejected(object.union(baseline, {"resource_changes": array.concat(baseline.resource_changes, [extra])}))
}
