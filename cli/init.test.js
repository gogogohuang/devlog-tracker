'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseArgs, run } = require('./init');

test('parseArgs accepts --claude, --codex and --cursor', () => {
  assert.deepEqual(parseArgs(['--claude']), { platforms: ['claude'] });
  assert.deepEqual(parseArgs(['--codex']), { platforms: ['codex'] });
  assert.deepEqual(parseArgs(['--claude', '--codex', '--cursor']), { platforms: ['claude', 'codex', 'cursor'] });
  assert.deepEqual(parseArgs([]), { platforms: [] });
});

test('parseArgs throws a clear error for unknown options', () => {
  assert.throws(
    () => parseArgs(['--foo']),
    { message: 'Unknown option: --foo (supported: --claude, --codex, --cursor)' }
  );
  assert.throws(() => parseArgs(['--codex', '-x']), /Unknown option: -x/);
});

test('run wraps platform install failures with vendoring context', async () => {
  const repoRoot = path.join(__dirname, '..');
  const targetDir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-init-'));
  fs.mkdirSync(path.join(targetDir, '.codex'), { recursive: true });
  fs.writeFileSync(path.join(targetDir, '.codex', 'hooks.json'), '{ not json');
  await assert.rejects(
    () => run(['--codex'], { repoRoot, targetDir, version: '0.0.0' }),
    (err) => {
      assert.match(err.message, /Installed files to .*\.devlog-tracker but failed to configure codex: /);
      assert.match(err.message, /Cannot parse existing/);
      assert.match(err.message, /re-run `devlog-tracker init` \(safe to re-run\)/);
      return true;
    }
  );
});
