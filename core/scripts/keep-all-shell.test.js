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

test('keep-all.sh rejects empty, blank and missing analysis sources; scan ignores the analysis file', () => {
  const result = spawnSync('bash', [
    path.join(__dirname, 'tests', 'test-keep-all.sh'),
  ], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout, /PASS: AC-5\/6: blank source preserves existing analysis/);
  assert.match(result.stdout, /PASS: AC-7: empty path preserves existing analysis/);
  if (!/SKIP: Node-dependent checks/.test(result.stdout)) {
    assert.match(result.stdout, /PASS: AC-11: scan output identical with analysis file present/);
  }
});
