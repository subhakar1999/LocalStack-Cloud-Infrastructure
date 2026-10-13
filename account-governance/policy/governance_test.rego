package main

import rego.v1

template := parse_config_file("../templates/s3-versioning.yaml")

test_baseline if {
    failures := deny with input as template
    count(failures) == 0
}

test_detect_wrong_resource_type if {
    modified := json.patch(template, [{"op": "replace", "path": "/Resources/S3VersioningRule/Properties/Scope/ComplianceResourceTypes", "value": ["AWS::EC2::Instance"]}])
    failures := deny with input as modified
    count(failures) > 0
}

test_refuse_suspending_versioning if {
    modified := json.patch(template, [{"op": "replace", "path": "/Resources/EnableS3Versioning/Properties/Parameters/VersioningState/StaticValue/Values", "value": ["Suspended"]}])
    failures := deny with input as modified
    count(failures) > 0
}

test_missing_remediation if {
    modified := json.patch(template, [{"op": "remove", "path": "/Resources/EnableS3Versioning"}])
    failures := deny with input as modified
    count(failures) > 0
}

test_cross_account_write_permissions_rejected if {
    modified := json.patch(template, [{"op": "remove", "path": "/Resources/VersioningRemediationRole/Properties/Policies/0/PolicyDocument/Statement/0/Condition"}])
    failures := deny with input as modified
    count(failures) > 0
}

test_excessive_permissions_rejected if {
    modified := json.patch(template, [{"op": "replace", "path": "/Resources/VersioningRemediationRole/Properties/Policies/0/PolicyDocument/Statement/0/Action", "value": ["s3:*"]}])
    failures := deny with input as modified
    count(failures) > 0
}
