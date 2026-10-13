package main

import rego.v1

valid_detection if {
    rule := input.Resources.S3VersioningRule
    rule.Type == "AWS::Config::ConfigRule"
    rule.Properties.Source.Owner == "AWS"
    rule.Properties.Source.SourceIdentifier == "S3_BUCKET_VERSIONING_ENABLED"
    rule.Properties.Scope.ComplianceResourceTypes == ["AWS::S3::Bucket"]
}
deny contains "S3-GOV-001: Detect disabled versioning for all recorded S3 buckets." if { not valid_detection }

valid_remediation if {
    remediation := input.Resources.EnableS3Versioning
    remediation.Type == "AWS::Config::RemediationConfiguration"
    props := remediation.Properties
    props.ConfigRuleName == {"Ref": "S3VersioningRule"}
    props.TargetType == "SSM_DOCUMENT"
    props.TargetId == "AWS-ConfigureS3BucketVersioning"
    props.TargetVersion == "1"
    props.ResourceType == "AWS::S3::Bucket"
    props.Parameters.BucketName.ResourceValue.Value == "RESOURCE_ID"
    props.Parameters.VersioningState.StaticValue.Values == ["Enabled"]
    props.Parameters.AutomationAssumeRole.StaticValue.Values == [{"Fn::GetAtt": ["VersioningRemediationRole", "Arn"]}]
    props.Automatic == {"Fn::If": ["RemediateAutomatically", true, false]}
    input.Conditions.RemediateAutomatically == {"Fn::Equals": [{"Ref": "AutomaticRemediation"}, "true"]}
    input.Parameters.AutomaticRemediation.Default == "true"
    props.MaximumAutomaticAttempts >= 1
    props.MaximumAutomaticAttempts <= 5
    props.RetryAttemptSeconds >= 60
}
deny contains "S3-GOV-002: Remediation must use the versioned AWS runbook to enable versioning on the evaluated bucket, with bounded retries." if { not valid_remediation }

valid_permissions if {
    role := input.Resources.VersioningRemediationRole
    role.Type == "AWS::IAM::Role"
    trust := role.Properties.AssumeRolePolicyDocument.Statement
    count(trust) == 1
    trust[0].Effect == "Allow"
    trust[0].Principal == {"Service": "ssm.amazonaws.com"}
    trust[0].Action == "sts:AssumeRole"
    trust[0].Condition.StringEquals["aws:SourceAccount"] == {"Ref": "AWS::AccountId"}
    trust[0].Condition.ArnLike["aws:SourceArn"] == {"Fn::Sub": "arn:${AWS::Partition}:ssm:${AWS::Region}:${AWS::AccountId}:automation-execution/*"}
    policies := role.Properties.Policies
    count(policies) == 1
    statements := policies[0].PolicyDocument.Statement
    count(statements) == 1
    s := statements[0]
    s.Effect == "Allow"
    {a | some a in s.Action} == {"s3:GetBucketVersioning", "s3:PutBucketVersioning"}
    s.Resource == {"Fn::Sub": "arn:${AWS::Partition}:s3:::*"}
    s.Condition.StringEquals["s3:ResourceAccount"] == {"Ref": "AWS::AccountId"}
    not role.Properties.ManagedPolicyArns
}
deny contains "S3-GOV-003: The remediation role must trust account-scoped SSM and grant only bucket-versioning permissions in that account." if { not valid_permissions }
