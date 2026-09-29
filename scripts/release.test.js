'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { release } = require('./release');

function makeRoot(version = '1.1.2') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-release-'));
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ version }));
  return root;
}

function fakeRun({ branch = 'main', dirty = '', counts = '0\t0' } = {}) {
  const calls = [];
  const run = (cmd, args) => {
    calls.push([cmd, ...args].join(' '));
    const key = calls.at(-1);
    if (key === 'git rev-parse --abbrev-ref HEAD') return branch;
    if (key === 'git status --porcelain') return dirty;
    if (key.startsWith('git rev-list')) return counts;
    return '';
  };
  return { run, calls };
}

test('minor bump runs test, version, push, release in order', () => {
  const { run, calls } = fakeRun();
  const result = release('minor', { run, root: makeRoot(), log: () => {} });
  assert.deepEqual(result, { current: '1.1.2', next: '1.2.0', tag: 'v1.2.0' });
  assert.deepEqual(calls.slice(-4), [
    'npm test',
    'pnpm version minor',
    'git push --follow-tags',
    'gh release create v1.2.0 --generate-notes',
  ]);
});

test('patch bump computes the next patch version', () => {
  const { run } = fakeRun();
  assert.equal(release('patch', { run, root: makeRoot(), log: () => {} }).tag, 'v1.1.3');
});

test('dry run performs preflight only', () => {
  const { run, calls } = fakeRun();
  release('minor', { run, root: makeRoot(), dryRun: true, log: () => {} });
  assert.ok(!calls.includes('npm test'));
});

test('refuses off main, dirty tree, behind or ahead of origin', () => {
  for (const opts of [{ branch: 'dev' }, { dirty: ' M x' }, { counts: '0\t2' }, { counts: '1\t0' }]) {
    const { run, calls } = fakeRun(opts);
    assert.throws(() => release('minor', { run, root: makeRoot(), log: () => {} }), /Cannot release/);
    assert.ok(!calls.includes('npm test'));
  }
});

test('rejects an unknown bump', () => {
  assert.throws(() => release('major', { run: fakeRun().run, root: makeRoot() }), /usage/);
});
