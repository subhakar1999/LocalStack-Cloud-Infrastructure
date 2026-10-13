#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const baseline = require('../policy/tests/fixtures.json').fixtures.valid;
const policyDir = path.resolve(__dirname, '../sentinel');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'sentinel-gate-'));
const cases = [
  ['valid', null, true],
  ['missing tag', p => { delete p.resource_changes.find(r => r.type === 'aws_s3_bucket').change.after.tags.Project; }, false],
  ['wrong environment', p => { p.resource_changes.find(r => r.type === 'aws_s3_bucket').change.after.tags.Environment = 'production'; }, false],
  ['suspended versioning', p => { p.resource_changes.find(r => r.type === 'aws_s3_bucket_versioning').change.after.versioning_configuration[0].status = 'Suspended'; }, false],
  ['removed protection', p => { p.resource_changes.find(r => r.type === 'aws_s3_bucket_versioning').change.after = null; }, false],
  ['public bucket', p => { p.resource_changes.find(r => r.type === 'aws_s3_bucket_public_access_block').change.after.block_public_policy = false; }, false],
  ['unknown encryption', p => { delete p.resource_changes.find(r => r.type === 'aws_s3_bucket_server_side_encryption_configuration').change.after.rule; }, false],
  ['destroy', p => { p.resource_changes.forEach(r => { r.change.after = null; }); }, false],
];
try {
  for (const [name, mutate, passes] of cases) {
    const plan = structuredClone(baseline);
    if (mutate) mutate(plan);
    const changes = Object.fromEntries(plan.resource_changes.map(r => [r.address, r]));
    const mock = path.join(temporary, 'tfplan.sentinel');
    fs.writeFileSync(mock, `resource_changes = ${JSON.stringify(changes)}\nvariables = ${JSON.stringify(plan.variables)}\n`);
    const config = path.join(temporary, 'sentinel.json');
    fs.writeFileSync(config, JSON.stringify({
      mock: { 'tfplan/v2': { module: { source: mock } } },
      policy: Object.fromEntries(['required-tags', 's3-protections'].map(name => [name, {
        source: path.join(policyDir, `${name}.sentinel`), enforcement_level: 'hard-mandatory',
      }])),
    }));
    const result = spawnSync(process.env.SENTINEL_BIN || 'sentinel', ['apply', `-config=${config}`], { cwd: temporary, encoding: 'utf8' });
    if (result.error) throw result.error;
    assert.doesNotMatch(result.stdout + result.stderr, /Error:|error evaluating/i, `${name}: ${result.stdout}${result.stderr}`);
    assert.equal(result.status, passes ? 0 : 1, `${name}: ${result.stdout}${result.stderr}`);
    console.log(`PASS: ${name}`);
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
