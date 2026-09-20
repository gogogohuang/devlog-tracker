'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { vendor } = require('./vendor');

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-vendor-'));
}

function makeFakeRepo(dir) {
  fs.mkdirSync(path.join(dir, 'core', 'scripts'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'core', 'scripts', 'enforce-devlog.sh'), '#!/usr/bin/env bash\necho hi\n');
  fs.mkdirSync(path.join(dir, 'claude'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'claude', 'hooks.json'), '{"hooks":{}}\n');
  fs.mkdirSync(path.join(dir, 'codex', 'hooks'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'codex', 'hooks', 'on-stop.sh'), '#!/usr/bin/env bash\necho codex\n');
  fs.mkdirSync(path.join(dir, 'cursor', 'hooks'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'cursor', 'hooks', 'on-stop.sh'), '#!/usr/bin/env bash\necho cursor\n');
  fs.mkdirSync(path.join(dir, 'skills', 'devlog-tracker'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'skills', 'devlog-tracker', 'SKILL.md'), '# skill\n');
  fs.mkdirSync(path.join(dir, 'commands'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'commands', 'start.md'), '# start\n');
}

test('vendor copies the expected directories and stamps VERSION + env.sh', () => {
  const repoRoot = tmpdir();
  const targetDir = tmpdir();
  makeFakeRepo(repoRoot);

  const vendorRoot = vendor({ repoRoot, targetDir, version: '0.21.0' });

  assert.equal(vendorRoot, path.join(targetDir, '.devlog-tracker'));
  assert.ok(fs.existsSync(path.join(vendorRoot, 'core', 'scripts', 'enforce-devlog.sh')));
  assert.ok(fs.existsSync(path.join(vendorRoot, 'claude', 'hooks.json')));
  assert.ok(fs.existsSync(path.join(vendorRoot, 'codex', 'hooks', 'on-stop.sh')));
  assert.ok(fs.existsSync(path.join(vendorRoot, 'cursor', 'hooks', 'on-stop.sh')));
  assert.ok(fs.existsSync(path.join(vendorRoot, 'skills', 'devlog-tracker', 'SKILL.md')));
  assert.ok(fs.existsSync(path.join(vendorRoot, 'commands', 'start.md')));
  assert.equal(fs.readFileSync(path.join(vendorRoot, 'VERSION'), 'utf8'), '0.21.0\n');
  assert.equal(
    fs.readFileSync(path.join(vendorRoot, 'env.sh'), 'utf8'),
    `export DEVLOG_TRACKER_ROOT="${vendorRoot}"\n`
  );
});

test('vendor preserves the ../../core/scripts relative layout codex/cursor wrappers rely on', () => {
  const repoRoot = tmpdir();
  const targetDir = tmpdir();
  makeFakeRepo(repoRoot);

  const vendorRoot = vendor({ repoRoot, targetDir, version: '0.21.0' });

  const resolvedFromCodex = path.join(vendorRoot, 'codex', 'hooks', '..', '..', 'core', 'scripts', 'enforce-devlog.sh');
  assert.ok(fs.existsSync(resolvedFromCodex));
});

test('re-running vendor overwrites rather than duplicating', () => {
  const repoRoot = tmpdir();
  const targetDir = tmpdir();
  makeFakeRepo(repoRoot);

  vendor({ repoRoot, targetDir, version: '0.21.0' });
  fs.writeFileSync(path.join(repoRoot, 'commands', 'start.md'), '# start v2\n');
  const vendorRoot = vendor({ repoRoot, targetDir, version: '0.22.0' });

  assert.equal(fs.readFileSync(path.join(vendorRoot, 'commands', 'start.md'), 'utf8'), '# start v2\n');
  assert.equal(fs.readFileSync(path.join(vendorRoot, 'VERSION'), 'utf8'), '0.22.0\n');
});

test('env.sh escapes shell metacharacters in the vendor path', () => {
  const repoRoot = tmpdir();
  const parent = tmpdir();
  const targetDir = path.join(parent, 'a$(x)"b`c\\d');
  fs.mkdirSync(targetDir);
  makeFakeRepo(repoRoot);

  const vendorRoot = vendor({ repoRoot, targetDir, version: '0.21.0' });

  assert.equal(
    fs.readFileSync(path.join(vendorRoot, 'env.sh'), 'utf8'),
    `export DEVLOG_TRACKER_ROOT="${vendorRoot.replace(/[\\"$`]/g, '\\$&')}"\n`
  );
  assert.ok(fs.readFileSync(path.join(vendorRoot, 'env.sh'), 'utf8').includes('a\\$(x)\\"b\\`c\\\\d'));
});

test('re-running vendor after upgrade removes the stale hooks/scripts directory', () => {
  const repoRoot = tmpdir();
  const targetDir = tmpdir();
  makeFakeRepo(repoRoot);

  // Simulate a pre-upgrade install that used the old hooks/scripts layout.
  const vendorRoot = path.join(targetDir, '.devlog-tracker');
  fs.mkdirSync(path.join(vendorRoot, 'hooks', 'scripts'), { recursive: true });
  fs.writeFileSync(path.join(vendorRoot, 'hooks', 'scripts', 'enforce-devlog.sh'), '#!/usr/bin/env bash\necho old\n');

  vendor({ repoRoot, targetDir, version: '0.26.0' });

  assert.ok(!fs.existsSync(path.join(vendorRoot, 'hooks')), 'stale hooks/ directory should be removed');
  assert.ok(fs.existsSync(path.join(vendorRoot, 'core', 'scripts', 'enforce-devlog.sh')));
});
