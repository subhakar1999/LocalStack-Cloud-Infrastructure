#!/usr/bin/env node
'use strict';
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const cwd = path.resolve(__dirname, '../sentinel');
const result = spawnSync(process.env.SENTINEL_BIN || 'sentinel', ['apply'], {
  cwd, stdio: 'inherit',
});
if (result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
