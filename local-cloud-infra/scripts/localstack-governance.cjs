const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFile, spawnSync } = require('node:child_process');
const { promisify } = require('node:util');
const execute = promisify(execFile);
const policyDirectory = path.resolve(__dirname, '../policy/live');
const defaultConfig = path.resolve(__dirname, '../governance/localstack-accounts.json');

function validateConfig(config) {
  const endpoint = new URL(config.endpoint);
  const localHosts = ['localhost', '127.0.0.1', '[::1]', 'localstack', 'localhost.localstack.cloud'];
  if (!localHosts.includes(endpoint.hostname) || !['http:', 'https:'].includes(endpoint.protocol) ||
      endpoint.username || endpoint.password || !['', '/'].includes(endpoint.pathname) || endpoint.search) {
    throw new Error('This runner requires an explicit LocalStack endpoint on a local host.');
  }
  if (!Array.isArray(config.accounts) || config.accounts.length === 0) throw new Error('Configure at least one local account.');
  const ids = new Set();
  for (const account of config.accounts) {
    if (!/^\d{12}$/.test(account.id) || typeof account.id !== 'string' || !/^[a-z]{2}(-[a-z]+)+-\d+$/.test(account.region)) {
      throw new Error('Each local account requires a 12-digit ID and AWS Region.');
    }
    if (ids.has(account.id)) throw new Error(`Duplicate account ${account.id}; S3 inventory already covers all bucket Regions.`);
    ids.add(account.id);
  }
  return config;
}

async function awsCall(config, account, args) {
  validateConfig(config);
  const env = {
    ...process.env,
    // Numeric mock access keys select isolated LocalStack accounts. The existing
    // Terraform stack uses 'test', which maps to 000000000000.
    AWS_ACCESS_KEY_ID: account.id === '000000000000' ? 'test' : account.id,
    AWS_SECRET_ACCESS_KEY: 'test', AWS_SESSION_TOKEN: '',
    AWS_CONFIG_FILE: process.platform === 'win32' ? 'NUL' : '/dev/null',
    AWS_SHARED_CREDENTIALS_FILE: process.platform === 'win32' ? 'NUL' : '/dev/null',
    AWS_DEFAULT_REGION: account.region, AWS_REGION: account.region,
    AWS_EC2_METADATA_DISABLED: 'true', AWS_PAGER: '',
  };
  delete env.AWS_PROFILE;
  delete env.AWS_DEFAULT_PROFILE;
  const { stdout } = await execute('aws', [
    '--endpoint-url', config.endpoint, '--region', account.region,
    '--cli-connect-timeout', '5', '--cli-read-timeout', '10',
    ...args, '--output', 'json', '--no-cli-pager',
  ], { env, timeout: 30000, maxBuffer: 16 * 1024 * 1024 });
  return stdout.trim() ? JSON.parse(stdout) : {};
}

async function collectInventory(config, call = awsCall) {
  validateConfig(config);
  const snapshot = {
    schema_version: 1, generated_at: new Date().toISOString(),
    account_ids: config.accounts.map(a => a.id), scanned_account_ids: [], resources: [], errors: [],
  };
  for (const account of config.accounts) {
    let buckets;
    try {
      const listing = await call(config, account, ['s3api', 'list-buckets']);
      if (!Array.isArray(listing.Buckets)) throw new Error('Invalid bucket listing response.');
      buckets = listing.Buckets;
      snapshot.scanned_account_ids.push(account.id);
    } catch (error) {
      snapshot.errors.push({ message: `${account.id}: bucket inventory failed: ${(error.stderr || error.message).trim()}` });
      continue;
    }
    // Batch reads so a hundred resources do not require a hundred sequential
    // CLI processes, while keeping concurrent requests bounded.
    for (let index = 0; index < buckets.length; index += 8) {
      await Promise.all(buckets.slice(index, index + 8).map(async bucket => {
        const resource = { type: 'aws_s3_bucket', account_id: account.id, name: bucket.Name, versioning_status: 'UNKNOWN' };
        try {
          const versioning = await call(config, account, ['s3api', 'get-bucket-versioning', '--bucket', bucket.Name]);
          // S3 returns no Status for a bucket that has never enabled versioning.
          resource.versioning_status = versioning.Status || 'Disabled';
        } catch (error) {
          snapshot.errors.push({ message: `${account.id}/${bucket.Name}: versioning read failed: ${(error.stderr || error.message).trim()}` });
        }
        snapshot.resources.push(resource);
      }));
    }
  }
  return snapshot;
}

function evaluateInventory(snapshot, binary = process.env.CONFTEST_BIN || 'conftest') {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'localstack-governance-'));
  const file = path.join(directory, 'inventory.json');
  try {
    fs.writeFileSync(file, JSON.stringify(snapshot));
    const result = spawnSync(binary, ['test', file, '--policy', policyDirectory, '--namespace', 'localstack', '--rego-version', 'v1', '--output', 'json'], {
      encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    });
    if (result.error) throw result.error;
    if (![0, 1].includes(result.status)) throw new Error(`Policy evaluation failed: ${result.stderr.trim()}`);
    const failures = JSON.parse(result.stdout).flatMap(report => report.failures || []);
    if (result.status !== (failures.length ? 1 : 0)) throw new Error('Policy result and exit status disagree.');
    return failures;
  } finally {
    if (fs.existsSync(file)) fs.unlinkSync(file);
    fs.rmdirSync(directory);
  }
}

async function runOnce(config, { remediate = false, call = awsCall, evaluate = evaluateInventory } = {}) {
  const before = await collectInventory(config, call);
  const failures = evaluate(before);
  if (!remediate || failures.length === 0) return { exitCode: failures.length ? 1 : 0, snapshot: before, failures, remediations: [] };
  const remediations = [];
  for (const failure of failures) {
    const metadata = failure.metadata || {};
    if (metadata.policy_id !== 'S3-VERSIONING-001') continue;
    const resource = before.resources.find(r => r.account_id === metadata.account_id && r.name === metadata.bucket);
    // Unknown/read-failed resources are never modified. Remediation is limited
    // to the known policy ID and a fixed 'Enabled' operation.
    if (!resource || !['Disabled', 'Suspended'].includes(resource.versioning_status)) continue;
    const account = config.accounts.find(a => a.id === resource.account_id);
    try {
      await call(config, account, ['s3api', 'put-bucket-versioning', '--bucket', resource.name, '--versioning-configuration', '{"Status":"Enabled"}']);
      remediations.push({ account_id: account.id, bucket: resource.name, status: 'Enabled' });
    } catch (error) {
      remediations.push({ account_id: account.id, bucket: resource.name, error: (error.stderr || error.message).trim() });
    }
  }
  const after = await collectInventory(config, call);
  const remaining = evaluate(after);
  return { exitCode: remaining.length || remediations.some(r => r.error) ? 1 : 0, snapshot: after, failures: remaining, remediations };
}

function parseArguments(args) {
  const options = { config: defaultConfig, remediate: false, watch: 0 };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--check') continue;
    if (args[i] === '--remediate') options.remediate = true;
    else if (args[i] === '--config' && args[i + 1]) options.config = path.resolve(args[++i]);
    else if (args[i] === '--watch' && args[i + 1]) {
      options.watch = Number(args[++i]);
      if (!Number.isInteger(options.watch) || options.watch < 5) throw new Error('--watch requires an interval of at least 5 seconds.');
    } else throw new Error(`Unknown or incomplete option: ${args[i]}`);
  }
  if (args.includes('--check') && options.remediate) throw new Error('Select either --check or --remediate.');
  return options;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  do {
    // Reload the inventory scope each cycle so newly added accounts are scanned.
    const config = validateConfig(JSON.parse(fs.readFileSync(options.config, 'utf8')));
    const result = await runOnce(config, options);
    console.log(`${result.exitCode ? 'FAIL' : 'PASS'}: ${result.snapshot.resources.length} buckets across ${config.accounts.length} local accounts; ${result.failures.length} policy violations; ${result.remediations.length} remediation attempts.`);
    for (const failure of result.failures) console.error(failure.msg);
    for (const remediation of result.remediations) console.log(JSON.stringify(remediation));
    if (!options.watch) { process.exitCode = result.exitCode; return; }
    await new Promise(resolve => setTimeout(resolve, options.watch * 1000));
  } while (true);
}

if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 2; });
module.exports = { validateConfig, awsCall, collectInventory, evaluateInventory, runOnce, parseArguments };
