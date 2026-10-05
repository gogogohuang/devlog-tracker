'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseArgs, run } = require('./init');

test('parseArgs accepts --claude and --codex', () => {
  assert.deepEqual(parseArgs(['--claude']), { platforms: ['claude'], prune: false });
  assert.deepEqual(parseArgs(['--codex']), { platforms: ['codex'], prune: false });
  assert.deepEqual(parseArgs(['--claude', '--codex']), { platforms: ['claude', 'codex'], prune: false });
  assert.deepEqual(parseArgs([]), { platforms: [], prune: false });
});

test('parseArgs accepts --prune', () => {
  assert.deepEqual(parseArgs(['--prune']), { platforms: [], prune: true });
});

test('run --prune removes orphan hooks without vendoring', async () => {
  const targetDir = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-init-'));
  fs.mkdirSync(path.join(targetDir, '.claude'));
  const gone = path.join(targetDir, '.devlog-tracker', 'core', 'scripts', 'x.sh');
  fs.writeFileSync(
    path.join(targetDir, '.claude', 'settings.local.json'),
    JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: `bash "${gone}"` }] }] } })
  );
  const result = await run(['--prune'], { repoRoot: path.join(__dirname, '..'), targetDir, version: '0.0.0' });
  assert.deepEqual(result, { pruned: 1 });
  assert.equal(fs.existsSync(path.join(targetDir, '.devlog-tracker')), false);
});

test('parseArgs throws a clear error for unknown options', () => {
  assert.throws(
    () => parseArgs(['--foo']),
    { message: 'Unknown option: --foo (supported: --claude, --codex, --prune)' }
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
