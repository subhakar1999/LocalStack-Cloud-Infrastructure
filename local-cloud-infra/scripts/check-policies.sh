#!/usr/bin/env bash
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${stack_dir}"

command -v terraform >/dev/null
command -v conftest >/dev/null
command -v node >/dev/null

# Use precisely this plan for any subsequent deployment. Never re-plan after
# approval, or a different change could be applied without being evaluated.
terraform -chdir=terraform plan -input=false -out=policy.tfplan
terraform -chdir=terraform show -json policy.tfplan > terraform/policy.tfplan.json
conftest test terraform/policy.tfplan.json --policy policy --rego-version v1
node scripts/check-sentinel.cjs
