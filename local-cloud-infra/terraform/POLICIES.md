# Policy as code in CI/CD

## Sentinel alongside OPA

The shared gate now runs both Conftest and Sentinel 0.40.0 against the same
saved Terraform plan JSON. Either failure stops deployment. Install Sentinel
on PATH, or set `SENTINEL_BIN` to its executable path. Node.js is also required.

```sh
make sentinel-test      # Compliant fixture plus seven rejection cases
make policy             # Plan, OPA checks, then Sentinel checks
make apply-approved     # Run both gates, apply the checked saved plan
```

`make sentinel-check` evaluates an already exported
`terraform/policy.tfplan.json`. On PowerShell, use
`node scripts/test-sentinel-gate.cjs` and `node scripts/check-sentinel.cjs`.

The [Sentinel policy set](../sentinel/sentinel.hcl) uses hard-mandatory policies
for required Project/Environment/Name tags and S3 public access blocking,
BucketOwnerEnforced ownership, enabled versioning, and AES256/KMS encryption.
It checks surviving resources including unchanged resources and requires
associated protection resources in the same module. Unknown required values
fail. Empty/destroy plans are rejected. Other service-specific rules remain
covered by OPA; this is not full parity with the Rego policy suite.

[local.hcl](../sentinel/local.hcl) enables the Sentinel CLI's Terraform feature
and reads the exported plan through `tfplan/v2`. For HCP Terraform or Terraform
Enterprise, configure a VCS policy set using `local-cloud-infra/sentinel` and
exclude `local.hcl` from its configuration (use `sentinel.hcl` only); the platform
provides `tfplan/v2`. No hosted policy set has been created. Direct Terraform
apply still bypasses the local CLI gate.

References: [Sentinel Terraform import configuration](https://developer.hashicorp.com/sentinel/docs/features/terraform/tfplan-v2)
and [Sentinel CLI configuration](https://developer.hashicorp.com/sentinel/docs/configuration).

The [GitHub Actions workflow](../../.github/workflows/policy-as-code.yml) runs on
every pull request and push, and can also be started manually. Its gate is named
**Terraform policy gate**.

1. Install pinned Terraform 1.16.5 and Conftest 0.71.1 (Rego v1 / OPA).
2. Run Rego unit tests and verify the actual CLI accepts compliant plans and
   exits with code 1 for deliberately unsafe plans.
3. Start ephemeral LocalStack with dummy AWS credentials.
4. Initialize Terraform, check formatting, validate, and run module tests.
5. Save a Terraform plan, export JSON, and run Conftest policies against it.
6. On pushes only, apply **the same saved plan** after the gate succeeds. PR and
   manual runs do not apply. LocalStack is removed afterward.

Conftest violations exit nonzero. The shell propagates that status and GitHub
marks the job failed; the normal apply step is skipped. There is no
`continue-on-error`, warning-only mode or override in this gate.
This pipeline deploys to disposable LocalStack, not persistent AWS. It requires
no AWS secrets or HCP Terraform subscription.

## Policy coverage

Shared rules are in [terraform.rego](../policy/terraform.rego). Existing module
lifecycle conditions remain as safeguards for direct Terraform use.

| Resources | CI requirements |
| --- | --- |
| Tags | Non-empty Project, Environment and Name; Environment must match the plan variable |
| S3 | Public access blocked, ACLs disabled, versioning and AES256/KMS encryption enabled; all protection resources present and associated with the bucket |
| DynamoDB | On-demand billing; PITR outside local |
| SNS | Required tags; raw subscription to the expected SQS queue from the expected topic |
| SQS | DLQ retains 14 days; primary retains 1-14 days and no longer than DLQ; redrive to the expected DLQ after 1-10 attempts |
| Queue policy | Only SNS service may send to the expected queue, restricted to the expected topic SourceArn |
| IAM | Lambda-only trust; approved actions scoped to expected queue/table; expected execution role and policy attachment |
| Lambda | Approved Python runtime, timeout 1-30s, memory 128-1024 MB; enabled SQS source, batch 1-10, expected function/queue |
| Input and coverage | Valid non-empty plan; all stack resource types present; new resource types require an explicit policy |

Violations, malformed JSON policy documents and unknown required security values
fail the gate. Inventory includes unchanged resources, not only creates/updates.
Removing S3 protections is rejected. This gate is specific to this stack: it
requires its resource types, assumes one bucket per module, and rejects partial,
targeted or complete destroy plans. Use the existing manual destroy command for
teardown.

The local profile permits `force_destroy`, disabled DynamoDB PITR and the
existing wildcard CloudWatch log ARN. Non-local plans must remove those
exceptions. This baseline does not require customer-managed KMS keys or a
TLS-only S3 bucket policy and does not replace broader AWS security review.

## Known policy values before deployment

Policy documents use deterministic ARNs built from emulated account, region and
resource names. `localstack_account_id` defaults to `000000000000`, matching the
existing `test` credential setup. Dependency references and explicit module
dependencies preserve provisioning order. Bucket protections reference the known
bucket name. CI can inspect security values on the first plan, before creation.
For another emulated account, set that variable to match LocalStack credentials.
AWS partition `aws` is assumed.

## Run locally

Install Terraform, Conftest and Node.js, then from `local-cloud-infra`:

```sh
make policy-test
make up
make wait
make init
make policy
# Optional: repeat the gate and apply only the saved approved plan.
make apply-approved
```

Without Make:

```sh
conftest verify --policy policy --data policy/tests --rego-version v1
node scripts/test-policy-gate.cjs
bash scripts/check-policies.sh
terraform -chdir=terraform apply -input=false policy.tfplan
```

Run apply only when the policy command succeeds. Generated plans are ignored by
Git and not uploaded as workflow artifacts. Direct `make apply` retains its
original behavior and does not invoke Conftest; use `make apply-approved` for the
shared governance gate.

The [fixture](../policy/tests/fixtures.json) contains managed resource changes
from the root module's mocked Terraform test plan, with equivalent root variables
and plan format version. Rego tests mutate this baseline to verify rejections.
The Node smoke test verifies Conftest exit status. Module tests use plan-only
mocked providers (Terraform >=1.7); ordinary provisioning retains >=1.5.

## Require the result before merging

Commit and push the workflow to activate it. In GitHub branch protection or a
ruleset, require **Terraform policy gate**. Failed runs already block workflow
deployment; requiring this check also blocks PR merges. Repository branch
protection has not been changed by this implementation.

See [OPA Terraform integration](https://www.openpolicyagent.org/docs/terraform),
[Conftest](https://www.conftest.dev/) and
[Terraform lifecycle conditions](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle).
