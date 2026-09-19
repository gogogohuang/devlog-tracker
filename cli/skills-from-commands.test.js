'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { generateSkillsFromCommands } = require('./skills-from-commands');

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-skills-'));
}

test('generateSkillsFromCommands writes one SKILL.md per command file, using namePrefix', () => {
  const commandsDir = tmpdir();
  const targetSkillsDir = tmpdir();
  fs.writeFileSync(
    path.join(commandsDir, 'start.md'),
    '---\ndescription: 啟動追蹤\n---\n\n請執行以下步驟：\n1. 做事\n'
  );

  const written = generateSkillsFromCommands({ commandsDir, targetSkillsDir, namePrefix: 'devlog' });

  assert.equal(written.length, 1);
  const skillPath = path.join(targetSkillsDir, 'devlog-start', 'SKILL.md');
  assert.equal(written[0], skillPath);
  const content = fs.readFileSync(skillPath, 'utf8');
  assert.match(content, /^---\nname: devlog-start\ndescription: "啟動追蹤"\n---\n\n/);
  assert.match(content, /請執行以下步驟：/);
  assert.match(content, /使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。\n$/);
});

test('generateSkillsFromCommands ignores non-.md files', () => {
  const commandsDir = tmpdir();
  const targetSkillsDir = tmpdir();
  fs.writeFileSync(path.join(commandsDir, 'start.md'), '---\ndescription: x\n---\nbody');
  fs.writeFileSync(path.join(commandsDir, 'README.txt'), 'not a command');

  const written = generateSkillsFromCommands({ commandsDir, targetSkillsDir, namePrefix: 'devlog' });

  assert.equal(written.length, 1);
});

test('generateSkillsFromCommands uses a different prefix and target dir independently', () => {
  const commandsDir = tmpdir();
  const targetSkillsDir = tmpdir();
  fs.writeFileSync(path.join(commandsDir, 'status.md'), '---\ndescription: 查狀態\n---\nbody');

  generateSkillsFromCommands({ commandsDir, targetSkillsDir, namePrefix: 'claude-devlog' });

  assert.ok(fs.existsSync(path.join(targetSkillsDir, 'claude-devlog-status', 'SKILL.md')));
});
