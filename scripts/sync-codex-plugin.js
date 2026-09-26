#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { parseCommand } = require('../cli/skills-from-commands');

function* walkFiles(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* walkFiles(file);
    else if (entry.isFile()) yield file;
  }
}

function expectedFiles(root) {
  const files = new Map();
  const hookTemplate = fs.readFileSync(path.join(root, 'codex', 'hooks.json'), 'utf8');
  files.set('codex/plugin-hooks.json', hookTemplate.replaceAll('${DEVLOG_TRACKER_ROOT}', '${PLUGIN_ROOT}'));

  for (const file of fs.readdirSync(path.join(root, 'commands')).filter(name => name.endsWith('.md'))) {
    const name = `devlog-${path.basename(file, '.md')}`;
    const { description, body } = parseCommand(fs.readFileSync(path.join(root, 'commands', file), 'utf8'));
    files.set(
      `codex/skills/${name}/SKILL.md`,
      `---\nname: ${name}\ndescription: ${JSON.stringify(description)}\n---\n\n${body.trim()}\n\n使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。\n`
    );
  }

  const sourceSkillsDir = path.join(root, 'skills', 'devlog-tracker');
  for (const source of walkFiles(sourceSkillsDir)) {
    const relative = path.relative(path.join(root, 'skills'), source);
    files.set(path.join('codex', 'skills', relative), fs.readFileSync(source, 'utf8'));
  }
  return files;
}

function syncCodexPlugin(root, { check = false } = {}) {
  const expected = expectedFiles(root);
  const problems = [];
  for (const [relative, content] of expected) {
    const target = path.join(root, relative);
    if (check) {
      if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8') !== content) problems.push(relative);
    } else {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, content);
    }
  }
  const skillsDir = path.join(root, 'codex', 'skills');
  if (fs.existsSync(skillsDir)) {
    for (const file of walkFiles(skillsDir)) {
      const relative = path.relative(root, file);
      if (!expected.has(relative)) problems.push(relative);
    }
  }
  return problems;
}

if (require.main === module) {
  const problems = syncCodexPlugin(path.join(__dirname, '..'), { check: process.argv.includes('--check') });
  if (problems.length) {
    console.error(`Codex plugin files out of sync:\n- ${problems.join('\n- ')}`);
    process.exitCode = 1;
  }
}

module.exports = { syncCodexPlugin };
