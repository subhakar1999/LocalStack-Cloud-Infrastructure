const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluateAudit } = require('./audit-compliance.cjs');

const targets = [
  { Account: '111111111111', Region: 'us-east-1', Status: 'CURRENT' },
  { Account: '222222222222', Region: 'eu-west-1', Status: 'CURRENT' },
];
const compliant = targets.map(target => ({ AccountId: target.Account, AwsRegion: target.Region, Compliance: { ComplianceType: 'COMPLIANT' } }));

test('every deployed account and Region must pass', () => {
  assert.deepEqual(evaluateAudit(targets, compliant), []);
});
test('one violating account fails the organization audit', () => {
  const evaluations = structuredClone(compliant);
  evaluations[1].Compliance = { ComplianceType: 'NON_COMPLIANT', ComplianceContributorCount: { CappedCount: 4, CapExceeded: false } };
  assert.match(evaluateAudit(targets, evaluations)[0], /222222222222\/eu-west-1: NON_COMPLIANT \(4 resources\)/);
});
test('missing Region data cannot be interpreted as compliance', () => {
  assert.match(evaluateAudit(targets, [compliant[0]])[0], /no compliance evaluation/);
});
test('no deployments fails instead of vacuously passing', () => {
  assert.equal(evaluateAudit([], []).length, 1);
});
test('failed deployments fail even when old evaluations are compliant', () => {
  const failed = structuredClone(targets);
  failed[0].Status = 'OUTDATED';
  assert.match(evaluateAudit(failed, compliant)[0], /OUTDATED/);
});
