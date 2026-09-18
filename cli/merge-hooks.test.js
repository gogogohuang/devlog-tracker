'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { mergeHooksTemplate } = require('./merge-hooks');

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-merge-'));
}

test('creates the target file from the template when target is missing', () => {
  const dir = tmpdir();
  const templatePath = path.join(dir, 'template.json');
  fs.writeFileSync(
    templatePath,
    JSON.stringify({
      hooks: { Stop: [{ hooks: [{ type: 'command', command: 'bash "${DEVLOG_TRACKER_ROOT}/codex/hooks/on-stop.sh"' }] }] },
    })
  );
  const targetPath = path.join(dir, '.codex', 'hooks.json');

  mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' });

  const written = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
  assert.equal(written.hooks.Stop[0].hooks[0].command, 'bash "/proj/.devlog-tracker/codex/hooks/on-stop.sh"');
});

test('re-running replaces only its own entries, keeps unrelated hooks untouched', () => {
  const dir = tmpdir();
  const templatePath = path.join(dir, 'template.json');
  fs.writeFileSync(
    templatePath,
    JSON.stringify({
      hooks: { Stop: [{ hooks: [{ type: 'command', command: 'bash "${DEVLOG_TRACKER_ROOT}/codex/hooks/on-stop.sh"' }] }] },
    })
  );
  const targetPath = path.join(dir, '.codex', 'hooks.json');
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(
    targetPath,
    JSON.stringify({
      hooks: {
        Stop: [
          { hooks: [{ type: 'command', command: 'bash /some/other-tool/on-stop.sh' }] },
          { hooks: [{ type: 'command', command: 'bash "/old/.devlog-tracker/codex/hooks/on-stop.sh"' }] },
        ],
      },
    })
  );

  mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' });

  const written = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
  assert.equal(written.hooks.Stop.length, 2);
  assert.equal(written.hooks.Stop[0].hooks[0].command, 'bash /some/other-tool/on-stop.sh');
  assert.equal(written.hooks.Stop[1].hooks[0].command, 'bash "/proj/.devlog-tracker/codex/hooks/on-stop.sh"');
});

test('preserves top-level non-hooks keys such as version', () => {
  const dir = tmpdir();
  const templatePath = path.join(dir, 'template.json');
  fs.writeFileSync(
    templatePath,
    JSON.stringify({
      version: 1,
      hooks: { stop: [{ command: 'bash "${DEVLOG_TRACKER_ROOT}/cursor/hooks/on-stop.sh"' }] },
    })
  );
  const targetPath = path.join(dir, '.cursor', 'hooks.json');

  mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' });

  const written = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
  assert.equal(written.version, 1);
  assert.equal(written.hooks.stop[0].command, 'bash "/proj/.devlog-tracker/cursor/hooks/on-stop.sh"');
});
