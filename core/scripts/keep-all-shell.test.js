'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawnSync } = require('child_process');

test('keep-all.sh writes, reports and replaces analysis; preserves it on missing source; works without Node', () => {
  const result = spawnSync('bash', [
    path.join(__dirname, 'tests', 'test-keep-all.sh'),
    '--write-analysis-tests-only',
  ], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});
