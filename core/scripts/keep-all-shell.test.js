'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawnSync } = require('child_process');

test('keep-all.sh analysis write failures preserve bytes, report errors and clean tmp and lock', () => {
  const result = spawnSync('bash', [
    path.join(__dirname, 'tests', 'test-keep-all.sh'),
    '--write-analysis-tests-only',
  ], { encoding: 'utf8' });
  assert.ifError(result.error);
  for (const operation of ['cp', 'mv']) {
    for (const contract of [
      `AC-8: ${operation} failure exits nonzero`,
      `AC-8: ${operation} failure has a stderr diagnostic`,
      `AC-8: ${operation} failure does not report ANALYSIS=`,
      `AC-8: ${operation} failure preserves existing analysis bytes`,
      `AC-9: ${operation} failure leaves no tmp`,
      `AC-10: ${operation} failure releases lock for immediate acquisition`,
    ]) assert.ok(result.stdout.includes(`PASS: ${contract}`), `${contract}\n${result.stdout}\n${result.stderr}`);
  }
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test('keep-all.sh --write-analysis refuses when another live process holds the lock', () => {
  const result = spawnSync('bash', [
    path.join(__dirname, 'tests', 'test-keep-all.sh'),
    '--write-analysis-tests-only',
  ], { encoding: 'utf8' });
  assert.ifError(result.error);
  for (const contract of [
    'AC-22: contended lock exits nonzero',
    'AC-22: contended lock has a stderr diagnostic',
    'AC-22: contended lock does not report ANALYSIS=',
    'AC-22: contended lock preserves existing analysis bytes',
    'AC-22: contended lock leaves no tmp',
    "AC-22: contended lock keeps the holder's lock and pid",
  ]) assert.ok(result.stdout.includes(`PASS: ${contract}`), `${contract}\n${result.stdout}\n${result.stderr}`);
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
    assert.match(result.stdout, /PASS: AC-12: apply with existing analysis exits 0/);
    assert.match(result.stdout, /PASS: AC-12: apply does not modify or delete existing analysis/);
    assert.match(result.stdout, /PASS: AC-12: apply does not create absent analysis/);
    assert.match(result.stdout, /PASS: AC-11: scan output identical with analysis file present/);
  }
});
