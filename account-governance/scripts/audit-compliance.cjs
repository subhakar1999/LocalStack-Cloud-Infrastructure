// Read-only organization audit: exit 1 on violations, incomplete deployment or
// missing evaluation data. The AWS CLI handles API pagination automatically.
const { spawnSync } = require('node:child_process');

function evaluateAudit(targets, evaluations) {
  const issues = [];
  if (!Array.isArray(targets) || targets.length === 0) {
    return ['No StackSet member deployments found; coverage cannot be established.'];
  }
  if (!Array.isArray(evaluations)) return ['Invalid AWS Config evaluation response.'];
  for (const target of targets) {
    const identity = `${target.Account}/${target.Region}`;
    if (target.Status !== 'CURRENT') issues.push(`${identity}: StackSet deployment is ${target.Status || 'unknown'}.`);
    const evaluation = evaluations.find(item => item.AccountId === target.Account && item.AwsRegion === target.Region);
    if (!evaluation) {
      issues.push(`${identity}: no compliance evaluation available yet.`);
    } else if (evaluation.Compliance?.ComplianceType !== 'COMPLIANT') {
      const count = evaluation.Compliance?.ComplianceContributorCount;
      const resources = count ? ` (${count.CapExceeded ? '>=' : ''}${count.CappedCount} resources)` : '';
      issues.push(`${identity}: ${evaluation.Compliance?.ComplianceType || 'unknown compliance'}${resources}.`);
    }
  }
  return issues;
}

function aws(args) {
  const result = spawnSync('aws', [...args, '--output', 'json', '--no-cli-pager'], {
    encoding: 'utf8', env: { ...process.env, AWS_PAGER: '' }, maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`AWS read failed: ${result.stderr.trim()}`);
  return JSON.parse(result.stdout);
}

if (require.main === module) {
  try {
    const required = ['GOVERNANCE_STACK_SET_NAME', 'GOVERNANCE_AGGREGATOR_NAME', 'GOVERNANCE_RULE_NAME'];
    for (const name of required) if (!process.env[name]) throw new Error(`Set ${name}.`);
    const deployment = aws(['cloudformation', 'list-stack-instances', '--stack-set-name', process.env.GOVERNANCE_STACK_SET_NAME,
      '--call-as', process.env.GOVERNANCE_CALL_AS || 'SELF']);
    const compliance = aws(['configservice', 'describe-aggregate-compliance-by-config-rules',
      '--configuration-aggregator-name', process.env.GOVERNANCE_AGGREGATOR_NAME,
      '--filters', JSON.stringify({ ConfigRuleName: process.env.GOVERNANCE_RULE_NAME })]);
    const issues = evaluateAudit(deployment.Summaries, compliance.AggregateComplianceByConfigRules);
    if (issues.length) {
      for (const issue of issues) console.error(issue);
      process.exitCode = 1;
    } else {
      console.log(`PASS: ${deployment.Summaries.length} account/Region deployments are compliant.`);
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { evaluateAudit };
