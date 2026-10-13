package localstack

import rego.v1

inventory(status) := {
    "schema_version": 1,
    "account_ids": ["000000000000"],
    "scanned_account_ids": ["000000000000"],
    "errors": [],
    "resources": [{"type": "aws_s3_bucket", "account_id": "000000000000", "name": "manually-created", "versioning_status": status}],
}

test_enabled_bucket_passes if {
    failures := deny with input as inventory("Enabled")
    count(failures) == 0
}
test_disabled_bucket_fails if {
    failures := deny with input as inventory("Disabled")
    count(failures) == 1
}
test_suspended_bucket_fails if {
    failures := deny with input as inventory("Suspended")
    count(failures) == 1
}
test_unknown_status_fails if {
    failures := deny with input as inventory("UNKNOWN")
    count(failures) == 1
}
test_missing_account_fails if {
    input_data := object.union(inventory("Enabled"), {"account_ids": ["000000000000", "111111111111"]})
    failures := deny with input as input_data
    count(failures) > 0
}
test_read_failure_fails if {
    input_data := object.union(inventory("Enabled"), {"errors": [{"message": "Cannot read bucket versioning"}]})
    failures := deny with input as input_data
    count(failures) > 0
}
test_empty_account_is_compliant if {
    input_data := object.union(inventory("Enabled"), {"resources": []})
    failures := deny with input as input_data
    count(failures) == 0
}
