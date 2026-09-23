'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { resolveScript, runCoreScript } = require('./core-script');

function tmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-core-'));
}
function writeScript(dir, name, body) {
  const scripts = path.join(dir, 'core', 'scripts');
  fs.mkdirSync(scripts, { recursive: true });
  fs.writeFileSync(path.join(scripts, name), body);
}

test('prefers the vendored copy and passes DEVLOG_PROJECT_DIR + args', () => {
  const target = tmp();
  const repo = tmp();
  writeScript(path.join(target, '.devlog-tracker'), 'x.sh', 'echo "vendored $DEVLOG_PROJECT_DIR $*"\n');
  writeScript(repo, 'x.sh', 'echo packaged\n');
  assert.equal(resolveScript({ targetDir: target, repoRoot: repo, name: 'x.sh' }),
    path.join(target, '.devlog-tracker', 'core', 'scripts', 'x.sh'));
  const r = runCoreScript({ targetDir: target, repoRoot: repo, name: 'x.sh', args: ['--json'] });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, `vendored ${target} --json\n`);
});

test('falls back to the packaged script when nothing is vendored', () => {
  const target = tmp();
  const repo = tmp();
  writeScript(repo, 'x.sh', 'echo packaged\n');
  const r = runCoreScript({ targetDir: target, repoRoot: repo, name: 'x.sh', args: [] });
  assert.equal(r.stdout, 'packaged\n');
});

test('propagates exit code and stderr', () => {
  const target = tmp();
  const repo = tmp();
  writeScript(repo, 'x.sh', 'echo oops >&2; exit 3\n');
  const r = runCoreScript({ targetDir: target, repoRoot: repo, name: 'x.sh', args: [] });
  assert.equal(r.status, 3);
  assert.equal(r.stderr, 'oops\n');
});

test('bin report runs the real packaged report-devlog.sh', () => {
  const cwd = tmp();
  const bin = path.join(__dirname, '..', 'bin', 'devlog-tracker.js');
  const r = spawnSync(process.execPath, [bin, 'report'], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, 'NOT_STARTED\n');
});
