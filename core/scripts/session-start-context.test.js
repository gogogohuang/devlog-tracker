'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = path.resolve(__dirname, '..', '..');
const ENTRIES = {
  claude: path.join(REPO, 'core', 'scripts', 'session-start-devlog.sh'),
  codex: path.join(REPO, 'codex', 'hooks', 'on-session-start.sh'),
  cursor: path.join(REPO, 'cursor', 'hooks', 'on-session-start.sh'),
};
const PLATFORMS = Object.keys(ENTRIES);
const MARK = 'ctx-switch-marker-7781';
const SUMMARY = 'summary-marker-5921';

function makeProject(t, withDevlog = true) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-ctx-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const cwd = path.join(dir, 'nested', 'working', 'directory');
  fs.mkdirSync(cwd, { recursive: true });
  if (withDevlog) {
    const d = path.join(dir, '.devlog');
    fs.mkdirSync(d);
    fs.writeFileSync(path.join(d, 'devlog.md'), [
      '# Project', '',
      '## Checkpoint', SUMMARY, '',
      '## Kept 索引', 'kept-index-marker-5922', '',
      '## Lessons 索引', 'lessons-index-marker-5923', '',
      '## Round 1 — 2026-09-09T12:00:00+08:00', '',
      '### Summary', SUMMARY, '',
      '### Handoff', '#### 現況', MARK, '',
      '### Status', 'DONE', '',
      '## Round 2 — 2026-09-09T13:00:00+08:00', '',
      '### User Input', '```text', 'open', '```', '',
    ].join('\n'));
    fs.writeFileSync(path.join(d, '.enabled'), 'enabled\n');
    fs.writeFileSync(path.join(d, '.round-open'), '{"round":2}\n');
    fs.writeFileSync(path.join(d, '.round-current.md'), `unfinished-round-marker ${MARK}\n`);
    fs.writeFileSync(path.join(d, '.span-open'), '{"round":2,"opened_at":"2026-09-09T13:00:00+08:00","ticks_since_checkin":1,"interval":3}\n');
    fs.writeFileSync(path.join(d, 'handoff.md'), `claude-handoff-marker ${MARK}\n`);
    fs.writeFileSync(path.join(d, 'handoff@codex.md'), `codex-handoff-marker ${MARK}\n`);
    fs.writeFileSync(path.join(d, 'handoff@cursor.md'), `cursor-handoff-marker ${MARK}\n`);
    fs.writeFileSync(path.join(d, '.span-open@codex'), '{"round":3,"opened_at":"2026-09-09T14:00:00+08:00"}\n');
    fs.writeFileSync(path.join(d, '.span-open@cursor'), '{"round":4,"opened_at":"2026-09-09T15:00:00+08:00"}\n');
  }
  return { dir, cwd };
}

function run(kind, project, { env: extraEnv = {}, input = {} } = {}) {
  const { dir, cwd } = project;
  const env = { ...process.env };
  for (const name of ['DEVLOG_SESSION_CONTEXT', 'DEVLOG_PLATFORM', 'DEVLOG_PROJECT_DIR', 'CLAUDE_PROJECT_DIR']) {
    delete env[name];
  }
  Object.assign(env, extraEnv);
  env.DEVLOG_PROJECT_DIR = dir;
  env.CLAUDE_PROJECT_DIR = dir;
  env.DEVLOG_PLATFORM = kind;
  return spawnSync('bash', [ENTRIES[kind]], {
    cwd,
    env,
    encoding: 'utf8',
    input: JSON.stringify({ source: 'startup', cwd: dir, workspace_roots: [dir], ...input }),
  });
}

function contextFrom(kind, result) {
  if (kind !== 'cursor') return result.stdout;
  return JSON.parse(result.stdout).additional_context;
}

function snapshotTree(root) {
  if (!fs.existsSync(root)) return null;
  const rows = [];
  function visit(dir, relative = '') {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const rel = path.posix.join(relative, entry.name);
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        rows.push({ path: rel, type: 'directory' });
        visit(full, rel);
      } else if (entry.isFile()) {
        rows.push({ path: rel, type: 'file', bytes: fs.readFileSync(full).toString('base64') });
      } else {
        rows.push({ path: rel, type: 'other' });
      }
    }
  }
  visit(root);
  return rows;
}

function assertSuccessfulResult(kind, result) {
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  if (kind === 'cursor') assert.doesNotThrow(() => JSON.parse(result.stdout));
}

for (const kind of PLATFORMS) {
  test(`${kind}: exact file value off suppresses all context and preserves .devlog bytes (AC-1, AC-2)`, (t) => {
    const project = makeProject(t);
    fs.writeFileSync(path.join(project.dir, '.devlog-session-context'), Buffer.from('off'));
    const before = snapshotTree(path.join(project.dir, '.devlog'));
    const result = run(kind, project);
    assertSuccessfulResult(kind, result);
    assert.equal(contextFrom(kind, result), '');
    assert.deepEqual(snapshotTree(path.join(project.dir, '.devlog')), before);
  });

  test(`${kind}: no project .devlog means off does not create any data`, (t) => {
    const project = makeProject(t, false);
    fs.writeFileSync(path.join(project.dir, '.devlog-session-context'), Buffer.from('off'));
    const result = run(kind, project);
    assertSuccessfulResult(kind, result);
    assert.equal(contextFrom(kind, result), '');
    assert.equal(fs.existsSync(path.join(project.dir, '.devlog')), false);
  });

  test(`${kind}: handoff and span files alone are suppressed without mutation`, (t) => {
    const project = makeProject(t, false);
    const d = path.join(project.dir, '.devlog');
    fs.mkdirSync(d);
    fs.writeFileSync(path.join(d, 'handoff@codex.md'), `only-handoff-marker ${MARK}\n`);
    fs.writeFileSync(path.join(d, '.span-open@codex'), '{"round":7,"opened_at":"2026-09-09T17:00:00+08:00"}\n');
    fs.writeFileSync(path.join(project.dir, '.devlog-session-context'), Buffer.from('off'));
    const before = snapshotTree(d);
    const result = run(kind, project);
    assertSuccessfulResult(kind, result);
    assert.equal(contextFrom(kind, result), '');
    assert.deepEqual(snapshotTree(d), before);
  });

  for (const [label, value] of [
    ['missing file', null],
    ['on', Buffer.from('on')],
    ['uppercase OFF', Buffer.from('OFF')],
    ['empty content', Buffer.from('')],
    ['whitespace', Buffer.from('  ')],
    ['trailing newline', Buffer.from('off\n')],
    ['NUL byte', Buffer.from([0])],
  ]) {
    test(`${kind}: ${label} keeps the default devlog summary`, (t) => {
      const project = makeProject(t);
      const switchFile = path.join(project.dir, '.devlog-session-context');
      if (value !== null) fs.writeFileSync(switchFile, value);
      const result = run(kind, project);
      assertSuccessfulResult(kind, result);
      assert.ok(contextFrom(kind, result).includes(SUMMARY), result.stdout);
      assert.ok(contextFrom(kind, result).includes(MARK), result.stdout);
    });
  }

  test(`${kind}: removing off restores the default devlog summary`, (t) => {
    const project = makeProject(t);
    const switchFile = path.join(project.dir, '.devlog-session-context');
    fs.writeFileSync(switchFile, Buffer.from('off'));
    const disabled = run(kind, project);
    assertSuccessfulResult(kind, disabled);
    assert.equal(contextFrom(kind, disabled), '');
    fs.unlinkSync(switchFile);
    const enabled = run(kind, project);
    assertSuccessfulResult(kind, enabled);
    assert.ok(contextFrom(kind, enabled).includes(SUMMARY), enabled.stdout);
  });

  test(`${kind}: legacy environment off does not disable the default summary`, (t) => {
    const project = makeProject(t);
    const result = run(kind, project, { env: { DEVLOG_SESSION_CONTEXT: 'off' } });
    assertSuccessfulResult(kind, result);
    assert.ok(contextFrom(kind, result).includes(SUMMARY), result.stdout);
  });
}

test('all platform state, legacy claim, and feature branch migration remain untouched when file switch is off', (t) => {
  const project = makeProject(t);
  const git = (args) => {
    const result = spawnSync('git', args, { cwd: project.dir, encoding: 'utf8' });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
  };
  git(['init', '-q', '-b', 'main']);
  git(['config', 'user.email', 'session-context@example.invalid']);
  git(['config', 'user.name', 'Session Context Test']);
  git(['add', '.devlog']);
  git(['commit', '-qm', 'seed main devlog']);
  git(['checkout', '-qb', 'feature/context-switch']);
  const devlog = path.join(project.dir, '.devlog');
  fs.writeFileSync(path.join(devlog, 'devlog.md'), [
    '# Project', '', '## Round 1 — 2026-09-09T12:00:00+08:00', '',
    '### Summary', 'branch-migration-marker', '', '### Status', 'IN_PROGRESS', '',
  ].join('\n'));
  fs.writeFileSync(path.join(devlog, 'handoff.md'), 'branch-handoff-marker\n');
  fs.rmSync(path.join(devlog, '.platform-claimed'), { force: true });
  fs.writeFileSync(path.join(devlog, '.round-open'), '{"round":9}\n');
  fs.writeFileSync(path.join(project.dir, '.devlog-session-context'), Buffer.from('off'));
  const before = snapshotTree(devlog);
  for (const kind of PLATFORMS) {
    const result = run(kind, project);
    assertSuccessfulResult(kind, result);
    assert.equal(contextFrom(kind, result), '');
    assert.deepEqual(snapshotTree(devlog), before, `${kind} changed .devlog state`);
  }
});

test('claude: source=clear stays empty without the file switch', (t) => {
  const project = makeProject(t);
  const result = run('claude', project, { input: { source: 'clear' } });
  assertSuccessfulResult('claude', result);
  assert.equal(result.stdout, '');
});
