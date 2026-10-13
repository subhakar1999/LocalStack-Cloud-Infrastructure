package localstack

import rego.v1

valid_inventory if {
    input.schema_version == 1
    is_array(input.account_ids)
    count(input.account_ids) > 0
    is_array(input.scanned_account_ids)
    is_array(input.resources)
    is_array(input.errors)
    every account in input.account_ids {
        regex.match("^[0-9]{12}$", account)
        account in input.scanned_account_ids
    }
    every resource in input.resources {
        resource.account_id in input.account_ids
        is_string(resource.name)
        resource.name != ""
        is_string(resource.type)
    }
}

deny contains {"msg": "LIVE-COVERAGE-001: Every configured account must be scanned successfully.", "policy_id": "LIVE-COVERAGE-001"} if {
    not valid_inventory
}

deny contains {"msg": sprintf("LIVE-READ-001: %s", [error.message]), "policy_id": "LIVE-READ-001"} if {
    some error in input.errors
}

deny contains {"msg": sprintf("LIVE-COVERAGE-002: Unsupported resource type %s.", [r.type]), "policy_id": "LIVE-COVERAGE-002"} if {
    some r in input.resources
    r.type != "aws_s3_bucket"
}

deny contains violation if {
    some bucket in input.resources
    bucket.type == "aws_s3_bucket"
    object.get(bucket, "versioning_status", "UNKNOWN") != "Enabled"
    violation := {
        "msg": sprintf("S3-VERSIONING-001: %s/%s must have versioning Enabled (currently %s).", [bucket.account_id, bucket.name, object.get(bucket, "versioning_status", "UNKNOWN")]),
        "policy_id": "S3-VERSIONING-001",
        "account_id": bucket.account_id,
        "bucket": bucket.name,
    }
}
