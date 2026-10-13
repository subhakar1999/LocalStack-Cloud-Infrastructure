const test = require('node:test');
const assert = require('node:assert/strict');
const { validateConfig, collectInventory, evaluateInventory, runOnce } = require('./localstack-governance.cjs');
const config = require('../governance/localstack-accounts.json');

function fakeS3(initial) {
  const buckets = structuredClone(initial);
  const writes = [];
  const call = async (_, account, args) => {
    const owned = buckets[account.id] || {};
    if (args[1] === 'list-buckets') return { Buckets: Object.keys(owned).map(Name => ({ Name })) };
    const name = args[args.indexOf('--bucket') + 1];
    if (owned[name] === 'ERROR') throw new Error('AccessDenied');
    if (args[1] === 'get-bucket-versioning') return owned[name] === 'Disabled' ? {} : { Status: owned[name] };
    if (args[1] === 'put-bucket-versioning') {
      const state = JSON.parse(args[args.indexOf('--versioning-configuration') + 1]).Status;
      writes.push({ account: account.id, name, state });
      owned[name] = state;
      return {};
    }
    throw new Error(`Unexpected operation ${args[1]}`);
  };
  return { buckets, writes, call };
}

test('only explicit local endpoints and mock account IDs are accepted', () => {
  assert.equal(validateConfig(config), config);
  assert.throws(() => validateConfig({ ...config, endpoint: 'https://s3.amazonaws.com' }), /local host/);
  assert.throws(() => validateConfig({ ...config, accounts: [] }), /at least one/);
  assert.throws(() => validateConfig({ ...config, accounts: [config.accounts[0], config.accounts[0]] }), /Duplicate/);
});
test('check detects manually maintained buckets across accounts without changing them', async () => {
  const service = fakeS3({ '000000000000': { terraform: 'Enabled', manual: 'Disabled' }, '111111111111': { 'other-team': 'Suspended' } });
  const result = await runOnce(config, { call: service.call });
  assert.equal(result.exitCode, 1);
  assert.equal(result.failures.length, 2);
  assert.equal(result.snapshot.resources.length, 3);
  assert.deepEqual(service.writes, []);
});
test('remediation changes only violating buckets and verifies them with OPA', async () => {
  const service = fakeS3({ '000000000000': { terraform: 'Enabled', manual: 'Disabled' }, '111111111111': { 'other-team': 'Suspended' } });
  const result = await runOnce(config, { remediate: true, call: service.call });
  assert.equal(result.exitCode, 0);
  assert.equal(service.writes.length, 2);
  assert.ok(service.writes.every(write => write.state === 'Enabled' && write.name !== 'terraform'));
});
test('future buckets are discovered and repaired on the next scan', async () => {
  const service = fakeS3({ '000000000000': {}, '111111111111': {} });
  assert.equal((await runOnce(config, { call: service.call })).exitCode, 0);
  service.buckets['111111111111'].future = 'Disabled';
  assert.equal((await runOnce(config, { call: service.call })).exitCode, 1);
  assert.equal((await runOnce(config, { remediate: true, call: service.call })).exitCode, 0);
});
test('failed reads fail the gate and never trigger blind writes', async () => {
  const service = fakeS3({ '000000000000': { inaccessible: 'ERROR' }, '111111111111': {} });
  const result = await runOnce(config, { remediate: true, call: service.call });
  assert.equal(result.exitCode, 1);
  assert.deepEqual(service.writes, []);
});
test('an unreadable account fails inventory coverage', async () => {
  const snapshot = await collectInventory(config, async (_, account) => {
    if (account.id === '111111111111') throw new Error('Cannot connect');
    return { Buckets: [] };
  });
  assert.equal(snapshot.errors.length, 1);
  assert.ok(evaluateInventory(snapshot).length > 0);
});
