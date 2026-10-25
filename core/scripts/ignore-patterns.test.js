'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = path.resolve(__dirname, '..', '..');

test('tests/test-ignore-patterns.sh passes', () => {
  const r = spawnSync('bash', [path.join(REPO, 'core', 'scripts', 'tests', 'test-ignore-patterns.sh')], {
    cwd: REPO,
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, r.stdout + r.stderr);
});
