// Exercise actual S3 APIs and OPA in isolated, randomly selected local accounts.
const assert = require('node:assert/strict');
const { randomInt, randomUUID } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFile } = require('node:child_process');
const execute = require('node:util').promisify(execFile);
const { awsCall, runOnce } = require('./localstack-governance.cjs');

async function main() {
  const first = randomInt(100000000000, 900000000000);
  const config = {
    endpoint: process.env.LOCALSTACK_ENDPOINT || 'http://localhost:4566',
    accounts: [{ id: String(first), region: 'us-east-1' }, { id: String(first + 1), region: 'us-east-1' }],
  };
  const prefix = `governance-demo-${randomUUID().slice(0, 8)}`;
  const created = [];
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'governance-demo-'));
  const configFile = path.join(directory, 'accounts.json');
  fs.writeFileSync(configFile, JSON.stringify(config));
  async function create(account, suffix) {
    const name = `${prefix}-${suffix}`;
    await awsCall(config, account, ['s3api', 'create-bucket', '--bucket', name]);
    created.push({ account, name });
    return name;
  }
  try {
    const disabled = await create(config.accounts[0], 'manual');
    const suspended = await create(config.accounts[1], 'other-team');
    await awsCall(config, config.accounts[1], ['s3api', 'put-bucket-versioning', '--bucket', suspended, '--versioning-configuration', '{"Status":"Enabled"}']);
    await awsCall(config, config.accounts[1], ['s3api', 'put-bucket-versioning', '--bucket', suspended, '--versioning-configuration', '{"Status":"Suspended"}']);

    const before = await runOnce(config);
    assert.equal(before.exitCode, 1, 'Unsafe resources must fail the policy gate');
    assert.equal(before.snapshot.resources.length, 2, 'Both local accounts must be scanned');
    assert.ok(before.snapshot.resources.some(r => r.name === disabled && r.versioning_status === 'Disabled'));
    assert.ok(before.snapshot.resources.some(r => r.name === suspended && r.versioning_status === 'Suspended'));
    console.log('PASS: manually created buckets in two accounts fail the policy gate.');
    await assert.rejects(execute(process.execPath, [path.join(__dirname, 'localstack-governance.cjs'), '--config', configFile, '--check']),
      error => error.code === 1, 'The actual CI command must return exit code 1 for policy violations');
    console.log('PASS: the actual check command exits with code 1 on violations.');

    const repaired = await runOnce(config, { remediate: true });
    assert.equal(repaired.exitCode, 0);
    assert.equal(repaired.remediations.length, 2);
    console.log('PASS: remediation enables versioning and the recheck passes.');

    await create(config.accounts[0], 'future');
    assert.equal((await runOnce(config)).exitCode, 1);
    assert.equal((await runOnce(config, { remediate: true })).exitCode, 0);
    assert.equal((await runOnce(config)).exitCode, 0);
    console.log('PASS: a future bucket is detected, repaired and verified.');
  } finally {
    // Only our newly created, empty fixture buckets are removed.
    for (const { account, name } of created) {
      await awsCall(config, account, ['s3api', 'delete-bucket', '--bucket', name]);
    }
    fs.unlinkSync(configFile);
    fs.rmdirSync(directory);
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
