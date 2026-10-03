'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { findStaleHooks, pruneStaleHooks } = require('./stale-hooks');

function setup() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-stale-'));
  fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
  fs.mkdirSync(path.join(dir, '.devlog-tracker'), { recursive: true });
  const alive = path.join(dir, '.devlog-tracker', 'alive.sh');
  fs.writeFileSync(alive, '');
  const gone = path.join(dir, '.devlog-tracker', 'gone.sh');
  const file = path.join(dir, '.claude', 'settings.local.json');
  const hook = (c) => ({ hooks: [{ type: 'command', command: c }] });
  fs.writeFileSync(file, JSON.stringify({
    hooks: {
      Stop: [hook(`bash "${gone}"`)],
      PreToolUse: [hook(`bash "${alive}"`), hook(`bash "${gone}"`), hook('echo user-hook')],
    },
  }));
  return { dir, file };
}

test('findStaleHooks only reports missing vendored scripts', () => {
  const { dir } = setup();
  const rel = path.join('.claude', 'settings.local.json');
  assert.deepEqual(findStaleHooks(dir), [
    { file: rel, event: 'Stop', count: 1 },
    { file: rel, event: 'PreToolUse', count: 1 },
  ]);
});

test('pruneStaleHooks removes orphans and keeps live and user hooks', () => {
  const { dir, file } = setup();
  assert.equal(pruneStaleHooks(dir), 2);
  const hooks = JSON.parse(fs.readFileSync(file, 'utf8')).hooks;
  assert.equal(hooks.Stop, undefined);
  assert.equal(hooks.PreToolUse.length, 2);
  assert.deepEqual(findStaleHooks(dir), []);
});

test('no hook files means nothing stale', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-stale-'));
  assert.deepEqual(findStaleHooks(dir), []);
  assert.equal(pruneStaleHooks(dir), 0);
});
