'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = path.resolve(__dirname, '..', '..');
const ON = path.join(REPO, 'core', 'scripts', 'session-context-on.sh');
const ENTRIES = {
  claude: path.join(REPO, 'core', 'scripts', 'session-start-devlog.sh'),
  codex: path.join(REPO, 'codex', 'hooks', 'on-session-start.sh'),
  cursor: path.join(REPO, 'cursor', 'hooks', 'on-session-start.sh'),
};
const SUMMARY = 'session-context-on-summary-marker-9027';

function tmp(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-on-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return fs.realpathSync(dir);
}

function runOn(env, cwd) {
  const e = { ...process.env };
  for (const name of ['DEVLOG_PROJECT_DIR', 'CLAUDE_PROJECT_DIR', 'DEVLOG_TRACKER_ROOT', 'CLAUDE_PLUGIN_ROOT']) {
    delete e[name];
  }
  Object.assign(e, env);
  return spawnSync('bash', [ON], { cwd, env: e, encoding: 'utf8' });
}

function runSessionStart(kind, project, cwd) {
  const env = { ...process.env };
  for (const name of ['DEVLOG_SESSION_CONTEXT', 'DEVLOG_PLATFORM', 'DEVLOG_PROJECT_DIR', 'CLAUDE_PROJECT_DIR']) {
    delete env[name];
  }
  env.DEVLOG_PROJECT_DIR = project;
  env.CLAUDE_PROJECT_DIR = project;
  env.DEVLOG_PLATFORM = kind;
  return spawnSync('bash', [ENTRIES[kind]], {
    cwd,
    env,
    encoding: 'utf8',
    input: JSON.stringify({ source: 'startup', cwd: project, workspace_roots: [project] }),
  });
}

function contextFrom(kind, result) {
  if (kind !== 'cursor') return result.stdout;
  return JSON.parse(result.stdout).additional_context;
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

test('removes an existing off switch, reports success, and is idempotent when already enabled (AC-3, AC-5)', (t) => {
  const project = tmp(t);
  const file = path.join(project, '.devlog-session-context');
  fs.writeFileSync(file, 'off');

  const restored = runOn({ DEVLOG_PROJECT_DIR: project }, project);
  assert.equal(restored.status, 0, restored.stderr);
  assert.equal(restored.stdout.trim(), 'SESSION_CONTEXT_ENABLED');
  assert.equal(fs.existsSync(file), false);

  const alreadyEnabled = runOn({ DEVLOG_PROJECT_DIR: project }, project);
  assert.equal(alreadyEnabled.status, 0, alreadyEnabled.stderr);
  assert.equal(alreadyEnabled.stdout.trim(), 'SESSION_CONTEXT_ALREADY_ENABLED');
  assert.equal(fs.existsSync(file), false);
});

test('from another cwd removes only the target switch and preserves .devlog bytes (AC-7)', (t) => {
  const root = tmp(t);
  const project = path.join(root, 'target project');
  const cwd = path.join(root, 'working directory');
  const pluginRoot = path.join(root, 'simulated plugin root');
  fs.mkdirSync(project);
  fs.mkdirSync(cwd);
  fs.mkdirSync(pluginRoot);
  fs.mkdirSync(path.join(project, '.devlog'));
  fs.writeFileSync(path.join(project, '.devlog', 'devlog.md'), 'existing log\n');
  const before = snapshot(path.join(project, '.devlog'));
  fs.writeFileSync(path.join(project, '.devlog-session-context'), 'off');
  fs.writeFileSync(path.join(cwd, '.devlog-session-context'), 'cwd sentinel');
  fs.writeFileSync(path.join(pluginRoot, '.devlog-session-context'), 'plugin sentinel');

  const result = runOn({ DEVLOG_PROJECT_DIR: project, DEVLOG_TRACKER_ROOT: pluginRoot }, cwd);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'SESSION_CONTEXT_ENABLED');
  assert.equal(fs.existsSync(path.join(project, '.devlog-session-context')), false);
  assert.equal(fs.readFileSync(path.join(cwd, '.devlog-session-context'), 'utf8'), 'cwd sentinel');
  assert.equal(fs.readFileSync(path.join(pluginRoot, '.devlog-session-context'), 'utf8'), 'plugin sentinel');
  assert.deepEqual(snapshot(path.join(project, '.devlog')), before);
});

test('fails without deleting or reporting success when the switch cannot be removed', (t) => {
  const project = tmp(t);
  const file = path.join(project, '.devlog-session-context');
  fs.mkdirSync(file);
  assert.ok(fs.existsSync(ON), 'session-context-on.sh must exist');

  const result = runOn({ DEVLOG_PROJECT_DIR: project }, project);

  assert.notEqual(result.status, 0);
  assert.ok(!result.stdout.includes('SESSION_CONTEXT_ENABLED'));
  assert.ok(!result.stdout.includes('SESSION_CONTEXT_ALREADY_ENABLED'));
  assert.equal(fs.statSync(file).isDirectory(), true);
});

test('requires an existing absolute DEVLOG_PROJECT_DIR and never falls back to another root (AC-7)', (t) => {
  const root = tmp(t);
  const cwd = path.join(root, 'cwd');
  const otherProject = path.join(root, 'other-project');
  fs.mkdirSync(cwd);
  fs.mkdirSync(otherProject);
  fs.writeFileSync(path.join(otherProject, '.devlog-session-context'), 'off');
  fs.writeFileSync(path.join(root, 'not-a-directory'), 'x');
  assert.ok(fs.existsSync(ON), 'session-context-on.sh must exist');
  const cases = [
    { CLAUDE_PROJECT_DIR: otherProject },
    { DEVLOG_PROJECT_DIR: '' },
    { DEVLOG_PROJECT_DIR: '.' },
    { DEVLOG_PROJECT_DIR: 'other-project' },
    { DEVLOG_PROJECT_DIR: path.join(root, 'missing') },
    { DEVLOG_PROJECT_DIR: path.join(root, 'not-a-directory') },
  ];
  for (const env of cases) {
    const result = runOn(env, cwd);
    assert.notEqual(result.status, 0, JSON.stringify(env));
    assert.ok(!result.stdout.includes('SESSION_CONTEXT_ENABLED'), JSON.stringify(env));
    assert.ok(!result.stdout.includes('SESSION_CONTEXT_ALREADY_ENABLED'), JSON.stringify(env));
    assert.equal(fs.readFileSync(path.join(otherProject, '.devlog-session-context'), 'utf8'), 'off');
    assert.equal(fs.existsSync(path.join(cwd, '.devlog-session-context')), false);
  }
});

test('command reports both outcomes accurately and its Codex skill is generated in sync', () => {
  const doc = fs.readFileSync(path.join(REPO, 'commands', 'session-context-on.md'), 'utf8');
  assert.match(doc, /session-context-on\.sh/);
  assert.match(doc, /SESSION_CONTEXT_ENABLED/);
  assert.match(doc, /SESSION_CONTEXT_ALREADY_ENABLED/);
  assert.match(doc, /已恢復預設|恢復預設/);
  assert.match(doc, /原本已是預設|已是預設模式/);
  assert.match(doc, /失敗/);
  assert.ok(fs.existsSync(path.join(REPO, 'codex', 'skills', 'devlog-session-context-on', 'SKILL.md')));
  const result = spawnSync(process.execPath, [path.join(REPO, 'scripts', 'sync-codex-plugin.js'), '--check'], {
    cwd: REPO,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

for (const kind of Object.keys(ENTRIES)) {
  test(`${kind}: removing the off switch restores the existing SessionStart summary (AC-4)`, (t) => {
    const project = tmp(t);
    const cwd = path.join(project, 'nested', 'working');
    const devlog = path.join(project, '.devlog');
    fs.mkdirSync(cwd, { recursive: true });
    fs.mkdirSync(devlog);
    fs.writeFileSync(path.join(devlog, 'devlog.md'), [
      '# Project', '', '## Checkpoint', SUMMARY, '',
      '## Round 1 — 2026-09-09T12:00:00+08:00', '',
      '### Summary', SUMMARY, '', '### Handoff', '#### 現況', 'existing handoff', '',
      '### Status', 'DONE', '',
    ].join('\n'));
    fs.writeFileSync(path.join(devlog, '.enabled'), 'enabled\n');
    // SessionStart claims the project once; seed the expected empty marker so
    // the snapshot measures changes to existing .devlog data only.
    fs.writeFileSync(path.join(devlog, '.platform-claimed'), '');
    const before = snapshot(devlog);
    fs.writeFileSync(path.join(project, '.devlog-session-context'), 'off');

    const restored = runOn({ DEVLOG_PROJECT_DIR: project }, cwd);
    assert.equal(restored.status, 0, restored.stderr);
    assert.equal(restored.stdout.trim(), 'SESSION_CONTEXT_ENABLED');
    const result = runSessionStart(kind, project, cwd);
    assert.equal(result.status, 0, result.stderr);
    assert.ok(contextFrom(kind, result).includes(SUMMARY), result.stdout);
    assert.deepEqual(snapshot(devlog), before);
  });
}
