# LocalStack account-wide policy as code

This is the current implementation for local use. It discovers S3 buckets through
the AWS API, evaluates their live configuration with OPA/Conftest and optionally
enables versioning. Buckets do not need to be in this repository's Terraform state:
manual buckets and buckets owned by another Terraform project are included.

The first rule is **S3 versioning must be Enabled**. Its code is in
[s3-versioning.rego](../policy/live/s3-versioning.rego). Edit and test that policy
through Git like application code. The runner implements a fixed, idempotent
remediation for this policy ID; other policies need their own collectors and
reviewed remediation handlers.

## Why a local runner

LocalStack documents that Config does not currently record changes to service
resources. Creating Config rules locally therefore does not establish automatic
compliance detection. This example reads actual S3 configuration and applies
policy results directly instead. It demonstrates detection/remediation behavior,
not production AWS Organizations, IAM or Config fidelity.

## Account scope

[localstack-accounts.json](localstack-accounts.json) selects the endpoint and mock
accounts. `000000000000` uses the existing `test` credentials; other 12-digit IDs
use the numeric mock access key that selects a LocalStack account. Secret keys
are always `test`. No real AWS profiles or credentials are used. The endpoint
must be on an explicitly allowed local hostname, so this runner cannot be pointed
at production AWS.

Each account's S3 listing covers its buckets across Regions, so list each account
once. The Region in this file configures API requests. Add more account IDs here
to expand the local scope. New buckets are discovered on every scan; new local
accounts must be added to the file. No workload resources are imported or adopted.

## Run

Install Node.js, AWS CLI and Conftest 0.71.1. Start LocalStack and wait for health.
From `local-cloud-infra`:

```sh
make up
make wait
make governance-check
make governance-remediate
```

Or use the scripts directly:

```sh
node scripts/localstack-governance.cjs --check
node scripts/localstack-governance.cjs --remediate
```

Check mode reads only and exits **1** if any policy fails. Remediation mode enables
versioning only on known violating buckets, reads their configuration again and
exits 1 if violations or remediation failures remain. Tool/configuration errors
exit **2**. Failed API reads fail the policy gate and are not treated as compliance.
An account successfully scanned with no buckets is compliant for this policy.

For ongoing correction of future buckets while developing:

```sh
make governance-watch
# Equivalent: node scripts/localstack-governance.cjs --remediate --watch 30
```

Watch mode reloads the account configuration each cycle, reports failures and
keeps running; stop it with Ctrl+C. For CI, use one-shot `--check`, whose nonzero
exit status fails the job. A bucket can be noncompliant until the next scan;
this is correction, not a synchronous deny of a console or API operation.

If Conftest is outside PATH, set `CONFTEST_BIN` to its executable path. You can
select another account configuration with `--config /path/to/accounts.json`.

## Verification and CI

```sh
conftest verify --policy policy/live --rego-version v1
node --test scripts/localstack-governance.test.cjs
node scripts/test-localstack-governance.cjs
```

The integration test uses randomly selected isolated LocalStack accounts. It
creates empty manual buckets, checks a disabled and a suspended bucket, verifies
the actual check command returns exit code 1, repairs them, then creates another
bucket to verify future-resource coverage. It deletes only those test buckets.

The [account governance workflow](../../.github/workflows/account-governance.yml)
runs those tests against LocalStack and performs a final read-only account check.
Require **LocalStack account governance gate** in branch protection to also block
PR merges. A fresh CI container does not contain resources from your workstation:
the integration fixtures prove the behavior, while local commands scan your local
instance. CI does not start a persistent watcher or configure real AWS credentials.

Terraform owners should also set versioning to Enabled in their own modules,
otherwise their applies can repeatedly undo the policy correction. Existing
versioning-enabled buckets are unchanged by remediation.

The [real-AWS governance templates](../../account-governance/README.md) remain a
separate future deployment reference. No real-AWS account/OU details are needed
to use this local implementation.

References: [LocalStack Config limitation](https://docs.localstack.cloud/aws/services/config/),
[LocalStack mock credentials](https://docs.localstack.cloud/aws/connecting/credentials/).
