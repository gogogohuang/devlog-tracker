'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawnSync } = require('child_process');

test('promote-sources.sh reports keep-all.analysis.md as a source (AC-13..AC-16)', () => {
  const result = spawnSync('bash', [path.join(__dirname, 'tests', 'test-promote.sh')], { encoding: 'utf8' });
  assert.ifError(result.error);
  for (const contract of [
    'AC-13: analysis with main devlog -> analysis row',
    'AC-13: kept row still present',
    'AC-14: analysis only (no main devlog) -> analysis row',
    'AC-14: analysis only -> not NO_SOURCES',
    'AC-15: no analysis -> unchanged output',
    'AC-15: no analysis -> no KIND=analysis row',
    'AC-16: nothing at all -> NO_SOURCES',
  ]) assert.ok(result.stdout.includes(`PASS: ${contract}`), `${contract}\n${result.stdout}\n${result.stderr}`);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});
