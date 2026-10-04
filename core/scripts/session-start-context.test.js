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

function makeProject() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-ctx-'));
  const d = path.join(dir, '.devlog');
  fs.mkdirSync(d);
  fs.writeFileSync(path.join(d, 'devlog.md'), `# Project\n\n## Round 1 — 2026-09-09T12:00:00+08:00\n\n### Summary\n${MARK}\n\n### Handoff\n#### 現況\n${MARK}\n\n### Status\nDONE\n\n## Round 2 — 2026-09-09T13:00:00+08:00\n\n### User Input\n\`\`\`text\nopen\n\`\`\`\n`);
  fs.writeFileSync(path.join(d, '.round-open'), '{"round":2}\n');
  fs.writeFileSync(path.join(d, '.round-current.md'), `unfinished ${MARK}\n`);
  fs.writeFileSync(path.join(d, '.span-open'), '{"round":2,"opened_at":"2026-09-09T13:00:00+08:00","ticks_since_checkin":1,"interval":3}\n');
  return dir;
}

function snapshot(dir) {
  const d = path.join(dir, '.devlog');
  return fs.readdirSync(d).sort().map((n) => [n, fs.readFileSync(path.join(d, n)).toString('base64')]);
}

function run(kind, dir, value, source = 'startup') {
  const env = { ...process.env, CLAUDE_PROJECT_DIR: dir, DEVLOG_PROJECT_DIR: dir };
  delete env.DEVLOG_SESSION_CONTEXT;
  if (value !== undefined) env.DEVLOG_SESSION_CONTEXT = value;
  return spawnSync('bash', [ENTRIES[kind]], {
    cwd: dir, env, encoding: 'utf8',
    input: JSON.stringify({ source, cwd: dir, workspace_roots: [dir] }),
  });
}

for (const kind of Object.keys(ENTRIES)) {
  test(`${kind}: DEVLOG_SESSION_CONTEXT=off injects nothing and leaves .devlog untouched (AC-1)`, () => {
    const dir = makeProject();
    const before = snapshot(dir);
    const r = run(kind, dir, 'off');
    assert.ifError(r.error);
    assert.equal(r.status, 0, r.stderr);
    assert.ok(!r.stdout.includes(MARK), r.stdout);
    for (const s of ['Round 1', '尚未收尾', 'span']) {
      assert.ok(!r.stdout.includes(s), `${s} in ${r.stdout}`);
    }
    if (kind === 'claude') assert.equal(r.stdout, '');
    else if (r.stdout.trim()) assert.ok(!JSON.parse(r.stdout).additional_context, r.stdout);
    assert.deepEqual(snapshot(dir), before);
  });

  for (const value of [undefined, '', 'on', 'OFF']) {
    test(`${kind}: DEVLOG_SESSION_CONTEXT=${JSON.stringify(value)} keeps default injection (AC-2)`, () => {
      const dir = makeProject();
      const r = run(kind, dir, value);
      assert.ifError(r.error);
      assert.equal(r.status, 0, r.stderr);
      assert.ok(r.stdout.includes(MARK), r.stdout);
    });
  }
}

test('claude: source=clear stays empty without the switch (AC-3)', () => {
  const dir = makeProject();
  const r = run('claude', dir, undefined, 'clear');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, '');
});
