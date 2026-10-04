'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = path.resolve(__dirname, '..', '..');
const OFF = path.join(REPO, 'core', 'scripts', 'session-context-off.sh');
const ENTRIES = {
  claude: path.join(REPO, 'core', 'scripts', 'session-start-devlog.sh'),
  codex: path.join(REPO, 'codex', 'hooks', 'on-session-start.sh'),
  cursor: path.join(REPO, 'cursor', 'hooks', 'on-session-start.sh'),
};
const MARK = 'off-cmd-marker-3318';

function tmp(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-off-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return fs.realpathSync(dir);
}

function runOff(env, cwd) {
  const e = { ...process.env };
  for (const n of ['DEVLOG_PROJECT_DIR', 'CLAUDE_PROJECT_DIR']) delete e[n];
  Object.assign(e, env);
  return spawnSync('bash', [OFF], { cwd, env: e, encoding: 'utf8' });
}

function snapshot(root) {
  const rows = [];
  (function visit(dir, rel) {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const r = path.posix.join(rel, ent.name);
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        rows.push([r, 'd']);
        visit(full, r);
      } else {
        rows.push([r, 'f', fs.readFileSync(full).toString('base64')]);
      }
    }
  })(root, '');
  return rows;
}

test('writes exactly "off" and prints SESSION_CONTEXT_DISABLED, repeatedly and over junk (AC-1)', (t) => {
  const proj = tmp(t);
  const file = path.join(proj, '.devlog-session-context');
  fs.writeFileSync(file, 'garbage content\nmore\n');
  for (let i = 0; i < 2; i++) {
    const r = runOff({ DEVLOG_PROJECT_DIR: proj }, proj);
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout.trim(), 'SESSION_CONTEXT_DISABLED');
    assert.deepEqual(fs.readFileSync(file), Buffer.from('off'));
  }
});

test('works from another cwd, with spaces in target, touching only the target file (AC-6)', (t) => {
  const root = tmp(t);
  const proj = path.join(root, 'my project dir');
  const cwd = path.join(root, 'elsewhere');
  fs.mkdirSync(proj);
  fs.mkdirSync(cwd);
  fs.mkdirSync(path.join(proj, '.devlog'));
  fs.writeFileSync(path.join(proj, '.devlog', 'devlog.md'), 'x\n');
  const before = snapshot(path.join(proj, '.devlog'));
  const r = runOff({ DEVLOG_PROJECT_DIR: proj, CLAUDE_PROJECT_DIR: cwd }, cwd);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(fs.readFileSync(path.join(proj, '.devlog-session-context')), Buffer.from('off'));
  assert.deepEqual(fs.readdirSync(cwd), []);
  assert.ok(!fs.existsSync(path.join(REPO, '.devlog-session-context')));
  assert.deepEqual(snapshot(path.join(proj, '.devlog')), before);
  assert.deepEqual(fs.readdirSync(proj).sort(), ['.devlog', '.devlog-session-context']);
});

test('fails without writing when DEVLOG_PROJECT_DIR is missing, relative or not a directory', (t) => {
  const root = tmp(t);
  const cwd = path.join(root, 'cwd');
  fs.mkdirSync(cwd);
  fs.writeFileSync(path.join(root, 'afile'), 'x');
  assert.ok(fs.existsSync(OFF), 'session-context-off.sh must exist');
  const cases = [
    {},
    { CLAUDE_PROJECT_DIR: cwd },
    { DEVLOG_PROJECT_DIR: '' },
    { DEVLOG_PROJECT_DIR: '.' },
    { DEVLOG_PROJECT_DIR: 'cwd' },
    { DEVLOG_PROJECT_DIR: path.join(root, 'missing') },
    { DEVLOG_PROJECT_DIR: path.join(root, 'afile') },
  ];
  for (const env of cases) {
    const r = runOff(env, root);
    assert.notEqual(r.status, 0, JSON.stringify(env));
    assert.ok(!r.stdout.includes('SESSION_CONTEXT_DISABLED'), JSON.stringify(env));
    assert.ok(!fs.existsSync(path.join(root, '.devlog-session-context')));
    assert.ok(!fs.existsSync(path.join(cwd, '.devlog-session-context')));
  }
});

test('write failure is not reported as success', (t) => {
  const proj = tmp(t);
  fs.mkdirSync(path.join(proj, '.devlog-session-context'));
  assert.ok(fs.existsSync(OFF), 'session-context-off.sh must exist');
  const r = runOff({ DEVLOG_PROJECT_DIR: proj }, proj);
  assert.notEqual(r.status, 0);
  assert.ok(!r.stdout.includes('SESSION_CONTEXT_DISABLED'));
  assert.ok(fs.statSync(path.join(proj, '.devlog-session-context')).isDirectory());
});

for (const kind of Object.keys(ENTRIES)) {
  test(`${kind}: SessionStart emits no context after the off command (AC-2)`, (t) => {
    const proj = tmp(t);
    const cwd = path.join(proj, 'sub');
    fs.mkdirSync(cwd);
    const d = path.join(proj, '.devlog');
    fs.mkdirSync(d);
    fs.writeFileSync(path.join(d, 'devlog.md'), [
      '# Project', '', '## Round 1 — 2026-09-09T12:00:00+08:00', '',
      '### Summary', MARK, '', '### Handoff', '#### 現況', MARK, '', '### Status', 'DONE', '',
    ].join('\n'));
    fs.writeFileSync(path.join(d, '.enabled'), 'enabled\n');
    const off = runOff({ DEVLOG_PROJECT_DIR: proj }, cwd);
    assert.equal(off.status, 0, off.stderr);
    const env = { ...process.env, DEVLOG_PLATFORM: kind, DEVLOG_PROJECT_DIR: proj, CLAUDE_PROJECT_DIR: proj };
    delete env.DEVLOG_SESSION_CONTEXT;
    const r = spawnSync('bash', [ENTRIES[kind]], {
      cwd,
      env,
      encoding: 'utf8',
      input: JSON.stringify({ source: 'startup', cwd: proj, workspace_roots: [proj] }),
    });
    assert.equal(r.status, 0, r.stderr);
    const out = kind === 'cursor' ? JSON.parse(r.stdout).additional_context : r.stdout;
    assert.equal(out, '');
  });
}
