'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { install } = require('./claude');

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-claude-'));
}

function makeFakeRepo(dir) {
  fs.mkdirSync(path.join(dir, 'claude'), { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'claude', 'hooks.json'),
    JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'bash "${DEVLOG_TRACKER_ROOT}/core/scripts/enforce-devlog.sh"' }] }] } }, null, 2)
  );
  fs.mkdirSync(path.join(dir, 'commands'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'commands', 'start.md'), '---\ndescription: 啟動追蹤\n---\n\n步驟一。\n');
}

function makeVendorRoot(dir) {
  // Real vendorRoot is targetDir/.devlog-tracker, which contains the marker in its path
  const vendorRoot = path.join(dir, '.devlog-tracker');
  fs.mkdirSync(path.join(vendorRoot, 'commands'), { recursive: true });
  fs.writeFileSync(path.join(vendorRoot, 'commands', 'start.md'), '---\ndescription: 啟動追蹤\n---\n\n步驟一。\n');
  return vendorRoot;
}

test('install merges hooks into .claude/settings.local.json without touching other keys', () => {
  const repoRoot = tmpdir();
  const vendorParent = tmpdir();
  const targetDir = tmpdir();
  const vendorRoot = makeVendorRoot(vendorParent);
  makeFakeRepo(repoRoot);
  fs.mkdirSync(path.join(targetDir, '.claude'), { recursive: true });
  fs.writeFileSync(
    path.join(targetDir, '.claude', 'settings.local.json'),
    JSON.stringify({ permissions: { allow: ['Bash(ls:*)'] } }, null, 2)
  );

  install({ repoRoot, targetDir, vendorRoot });

  const settings = JSON.parse(fs.readFileSync(path.join(targetDir, '.claude', 'settings.local.json'), 'utf8'));
  assert.deepEqual(settings.permissions, { allow: ['Bash(ls:*)'] });
  assert.equal(settings.hooks.Stop[0].hooks[0].command, `bash "${vendorRoot}/core/scripts/enforce-devlog.sh"`);
});

test('install writes .claude/skills/devlog-<name>/SKILL.md from vendored commands', () => {
  const repoRoot = tmpdir();
  const vendorParent = tmpdir();
  const targetDir = tmpdir();
  const vendorRoot = makeVendorRoot(vendorParent);
  makeFakeRepo(repoRoot);

  install({ repoRoot, targetDir, vendorRoot });

  const skillPath = path.join(targetDir, '.claude', 'skills', 'devlog-start', 'SKILL.md');
  assert.ok(fs.existsSync(skillPath));
  assert.match(fs.readFileSync(skillPath, 'utf8'), /步驟一。/);
});

test('install upserts the devlog-tracker block into CLAUDE.md, leaving other content alone', () => {
  const repoRoot = tmpdir();
  const vendorParent = tmpdir();
  const targetDir = tmpdir();
  const vendorRoot = makeVendorRoot(vendorParent);
  makeFakeRepo(repoRoot);
  fs.writeFileSync(path.join(targetDir, 'CLAUDE.md'), '# My project\n\nSome existing notes.\n');

  install({ repoRoot, targetDir, vendorRoot });

  const content = fs.readFileSync(path.join(targetDir, 'CLAUDE.md'), 'utf8');
  assert.match(content, /# My project/);
  assert.match(content, /Some existing notes\./);
  assert.match(content, /<!-- devlog-tracker:begin -->/);
  assert.match(content, /<!-- devlog-tracker:end -->/);
  assert.match(content, /devlog-tracker/);
});

test('re-running install is idempotent: no duplicate hook entries or skill directories', () => {
  const repoRoot = tmpdir();
  const vendorParent = tmpdir();
  const targetDir = tmpdir();
  const vendorRoot = makeVendorRoot(vendorParent);
  makeFakeRepo(repoRoot);

  install({ repoRoot, targetDir, vendorRoot });
  const skillsAfterFirst = fs.readdirSync(path.join(targetDir, '.claude', 'skills'));
  install({ repoRoot, targetDir, vendorRoot });
  const skillsAfterSecond = fs.readdirSync(path.join(targetDir, '.claude', 'skills'));

  const settings = JSON.parse(fs.readFileSync(path.join(targetDir, '.claude', 'settings.local.json'), 'utf8'));
  assert.equal(settings.hooks.Stop.length, 1);
  assert.deepEqual(skillsAfterFirst, skillsAfterSecond, 'skill directories should not duplicate');
});

test('re-running install twice on existing CLAUDE.md keeps exactly one marker pair', () => {
  const repoRoot = tmpdir();
  const vendorParent = tmpdir();
  const targetDir = tmpdir();
  const vendorRoot = makeVendorRoot(vendorParent);
  makeFakeRepo(repoRoot);
  fs.writeFileSync(path.join(targetDir, 'CLAUDE.md'), '# My project\n\nSome existing notes.\n');

  install({ repoRoot, targetDir, vendorRoot });
  install({ repoRoot, targetDir, vendorRoot });

  const content = fs.readFileSync(path.join(targetDir, 'CLAUDE.md'), 'utf8');
  const beginCount = (content.match(/<!-- devlog-tracker:begin -->/g) || []).length;
  const endCount = (content.match(/<!-- devlog-tracker:end -->/g) || []).length;
  assert.equal(beginCount, 1, 'Should have exactly one begin marker');
  assert.equal(endCount, 1, 'Should have exactly one end marker');
  assert.match(content, /# My project/);
  assert.match(content, /Some existing notes\./);
});

test('install with real claude/hooks.json substitutes all placeholders and is idempotent', () => {
  const repoRoot = path.join(__dirname, '..', '..');
  const vendorParent = tmpdir();
  const targetDir = tmpdir();
  const vendorRoot = makeVendorRoot(vendorParent);

  // First run
  install({ repoRoot, targetDir, vendorRoot });

  const settingsPath = path.join(targetDir, '.claude', 'settings.local.json');
  const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));

  // Collect all commands from the merged hooks
  const commands = [];
  for (const event of Object.keys(settings.hooks)) {
    const entries = settings.hooks[event];
    for (const entry of entries) {
      if (entry.hooks) {
        for (const hook of entry.hooks) {
          if (hook.command) {
            commands.push(hook.command);
          }
        }
      }
    }
  }

  // Verify no unsubstituted placeholders remain
  for (const command of commands) {
    assert.ok(!command.includes('${'), `Command should not contain unsubstituted placeholder: ${command}`);
  }

  // Verify every command contains the vendorRoot and /core/scripts/
  for (const command of commands) {
    assert.ok(command.includes(vendorRoot), `Command should contain vendorRoot path: ${command}`);
    assert.ok(command.includes('/core/scripts/'), `Command should reference core/scripts: ${command}`);
  }

  // Now read the template to count expected entries per event
  const templatePath = path.join(repoRoot, 'claude', 'hooks.json');
  const template = JSON.parse(fs.readFileSync(templatePath, 'utf8'));

  // Before second run, get the current entry counts
  const entriesBeforeSecond = {};
  for (const event of Object.keys(template.hooks)) {
    entriesBeforeSecond[event] = settings.hooks[event] ? settings.hooks[event].length : 0;
  }

  // Second run
  install({ repoRoot, targetDir, vendorRoot });

  const settingsAfterSecond = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));

  // Verify no duplication: each event should have same count as template (1 entry each)
  for (const event of Object.keys(template.hooks)) {
    const expectedCount = template.hooks[event].length;
    const actualCount = settingsAfterSecond.hooks[event] ? settingsAfterSecond.hooks[event].length : 0;
    assert.equal(actualCount, expectedCount, `Event ${event} should have ${expectedCount} entry (template count), got ${actualCount}`);
  }
});
