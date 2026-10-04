'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawnSync } = require('child_process');

for (const name of ['test-workspace-snapshot.sh', 'test-round-start.sh']) {
  test(`${name} passes (workspace claim ignores branch label)`, () => {
    const result = spawnSync('bash', [path.join(__dirname, 'tests', name)], { encoding: 'utf8' });
    assert.ifError(result.error);
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  });
}
