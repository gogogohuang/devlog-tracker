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

function writeTemplate(dir) {
  const templatePath = path.join(dir, 'template.json');
  fs.writeFileSync(
    templatePath,
    JSON.stringify({
      hooks: { Stop: [{ hooks: [{ type: 'command', command: 'bash "${DEVLOG_TRACKER_ROOT}/codex/hooks/on-stop.sh"' }] }] },
    })
  );
  return templatePath;
}

function setup(existingText) {
  const dir = tmpdir();
  const templatePath = writeTemplate(dir);
  const targetPath = path.join(dir, '.codex', 'hooks.json');
  if (existingText !== undefined) {
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.writeFileSync(targetPath, existingText);
  }
  return { templatePath, targetPath };
}

test('malformed existing JSON throws with the file path and re-run guidance', () => {
  const { templatePath, targetPath } = setup('{ not json');
  assert.throws(
    () => mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' }),
    (err) => {
      assert.ok(err.message.startsWith(`Cannot parse existing ${targetPath}: `), err.message);
      assert.ok(err.message.includes('Fix or move the file, then re-run `devlog-tracker init` (safe to re-run).'));
      return true;
    }
  );
  assert.equal(fs.readFileSync(targetPath, 'utf8'), '{ not json');
});

test('non-object top-level value throws naming the file path', () => {
  for (const text of ['[]', '"str"', '42']) {
    const { templatePath, targetPath } = setup(text);
    assert.throws(
      () => mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' }),
      (err) => err.message.includes(targetPath),
      text
    );
  }
});

test('non-object "hooks" value throws naming the file path', () => {
  const { templatePath, targetPath } = setup('{"hooks": []}');
  assert.throws(
    () => mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' }),
    (err) => err.message.includes(targetPath) && err.message.includes('hooks')
  );
});

test('non-array event value throws naming the file path and event, without overwriting', () => {
  const original = '{"hooks": {"Stop": {"oops": true}}}';
  const { templatePath, targetPath } = setup(original);
  assert.throws(
    () => mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' }),
    (err) => err.message.includes(targetPath) && err.message.includes('Stop')
  );
  assert.equal(fs.readFileSync(targetPath, 'utf8'), original);
});

test('empty, whitespace-only and null existing files are treated as empty', () => {
  for (const text of ['', '  \n\t ', 'null']) {
    const { templatePath, targetPath } = setup(text);
    mergeHooksTemplate({ templatePath, targetPath, vendorRoot: '/proj/.devlog-tracker' });
    const written = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
    assert.equal(written.hooks.Stop[0].hooks[0].command, 'bash "/proj/.devlog-tracker/codex/hooks/on-stop.sh"');
  }
});

test('vendorRoot containing a double quote or backslash still yields valid JSON', () => {
  const vendorRoot = '/tmp/we"ird\\dir/.devlog-tracker';
  const { templatePath, targetPath } = setup();
  mergeHooksTemplate({ templatePath, targetPath, vendorRoot });
  const written = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
  assert.equal(written.hooks.Stop[0].hooks[0].command, `bash "${vendorRoot}/codex/hooks/on-stop.sh"`);
});

test('real templates quote the vendor path so project paths with spaces work', () => {
  const vendorRoot = '/tmp/my project/.devlog-tracker';
  for (const name of ['cursor', 'codex']) {
    const dir = tmpdir();
    const targetPath = path.join(dir, 'hooks.json');
    mergeHooksTemplate({
      templatePath: path.join(__dirname, '..', name, 'hooks.json'),
      targetPath,
      vendorRoot,
    });
    const written = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
    const commands = [];
    (function walk(v) {
      if (Array.isArray(v)) v.forEach(walk);
      else if (v && typeof v === 'object') {
        for (const [k, val] of Object.entries(v)) {
          if (k === 'command') commands.push(val);
          else walk(val);
        }
      }
    })(written.hooks);
    assert.ok(commands.length >= 5, `${name} has commands`);
    for (const c of commands) {
      assert.ok(c.includes(`"${vendorRoot}/`), `${name}: unquoted command ${c}`);
    }
  }
});
