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
const MARK = 'ctx-switch-marker-7781';

function makeProject(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-ctx-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const d = path.join(dir, '.devlog');
  fs.mkdirSync(d);
  fs.writeFileSync(path.join(d, 'devlog.md'), `# Project\n\n## Round 1 — 2026-09-09T12:00:00+08:00\n\n### Summary\n${MARK}\n\n### Handoff\n#### 現況\n${MARK}\n\n### Status\nDONE\n\n## Round 2 — 2026-09-09T13:00:00+08:00\n\n### User Input\n\`\`\`text\nopen\n\`\`\`\n`);
  fs.writeFileSync(path.join(d, '.round-open'), '{"round":2}\n');
  fs.writeFileSync(path.join(d, '.round-current.md'), `unfinished ${MARK}\n`);
  fs.writeFileSync(path.join(d, '.span-open'), '{"round":2,"opened_at":"2026-09-09T13:00:00+08:00","ticks_since_checkin":1,"interval":3}\n');
  return dir;
}

function run(kind, dir, source = 'startup') {
  const env = { ...process.env };
  for (const name of ['DEVLOG_SESSION_CONTEXT', 'DEVLOG_PLATFORM', 'DEVLOG_PROJECT_DIR', 'CLAUDE_PROJECT_DIR']) {
    delete env[name];
  }
  env.DEVLOG_PROJECT_DIR = dir;
  env.CLAUDE_PROJECT_DIR = dir;
  env.DEVLOG_PLATFORM = kind;
  return spawnSync('bash', [ENTRIES[kind]], {
    cwd: dir, env, encoding: 'utf8',
    input: JSON.stringify({ source, cwd: dir, workspace_roots: [dir] }),
  });
}

for (const kind of Object.keys(ENTRIES)) {
  test(`${kind}: injects the default summary without a file switch (AC-1)`, (t) => {
    const dir = makeProject(t);
    const r = run(kind, dir);
    assert.ifError(r.error);
    assert.equal(r.status, 0, r.stderr);
    if (kind === 'cursor') {
      const payload = JSON.parse(r.stdout);
      assert.equal(payload.additional_context.includes(MARK), true, r.stdout);
    } else {
      assert.ok(r.stdout.includes(MARK), r.stdout);
    }
  });
}

test('claude: source=clear stays empty without the switch (AC-5)', (t) => {
  const dir = makeProject(t);
  const r = run('claude', dir, 'clear');
  assert.ifError(r.error);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, '');
});
