// Exercise the actual CLI exit status used by CI, not only Rego assertions.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const stack = path.resolve(__dirname, '..');
const baseline = require('../policy/tests/fixtures.json').fixtures.valid;
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'terraform-policy-'));
const binary = process.env.CONFTEST_BIN || 'conftest';

function check(name, plan, expected) {
  const file = path.join(directory, `${name}.json`);
  fs.writeFileSync(file, JSON.stringify(plan));
  const result = spawnSync(binary, ['test', file, '--policy', path.join(stack, 'policy'),
    '--rego-version', 'v1', '--output', 'json'], { encoding: 'utf8' });
  if (result.error) throw result.error;
  assert.equal(result.status, expected, `${name}: ${result.stdout}\n${result.stderr}`);
  const reports = JSON.parse(result.stdout);
  const failures = reports.flatMap(report => report.failures || []);
  assert.equal(failures.length > 0, expected !== 0, `${name}: policy failure report`);
  console.log(`${name}: exit ${result.status}, ${failures.length} policy violations`);
}

function mutate(type, patch, remove = []) {
  const plan = structuredClone(baseline);
  const resource = plan.resource_changes.find(r => r.type === type);
  Object.assign(resource.change.after, patch);
  for (const key of remove) delete resource.change.after[key];
  return plan;
}

try {
  check('compliant-plan', baseline, 0);
  check('public-bucket', mutate('aws_s3_bucket_public_access_block', { block_public_policy: false }), 1);
  check('missing-tags', mutate('aws_s3_bucket', { tags: {} }), 1);
  const unknown = mutate('aws_iam_policy', {}, ['policy']);
  unknown.resource_changes.find(r => r.type === 'aws_iam_policy').change.after_unknown.policy = true;
  check('unknown-iam-policy', unknown, 1);
  check('invalid-input', {}, 1);
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
