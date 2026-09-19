'use strict';
const fs = require('fs');
const path = require('path');

function parseCommand(text) {
  const match = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(text);
  if (!match) return { description: '', body: text };
  const description = /^description:\s*(.*)$/m.exec(match[1]);
  return { description: description ? description[1].trim() : '', body: match[2] };
}

// 把 commandsDir 底下每個 *.md 轉成 targetSkillsDir/<namePrefix>-<檔名>/SKILL.md。
// 回傳寫入的 SKILL.md 絕對路徑陣列。
function generateSkillsFromCommands({ commandsDir, targetSkillsDir, namePrefix }) {
  const written = [];
  for (const file of fs.readdirSync(commandsDir)) {
    if (!file.endsWith('.md')) continue;
    const name = `${namePrefix}-${path.basename(file, '.md')}`;
    const { description, body } = parseCommand(fs.readFileSync(path.join(commandsDir, file), 'utf8'));
    const skillDir = path.join(targetSkillsDir, name);
    fs.mkdirSync(skillDir, { recursive: true });
    const skillPath = path.join(skillDir, 'SKILL.md');
    fs.writeFileSync(
      skillPath,
      `---\nname: ${name}\ndescription: ${JSON.stringify(description)}\n---\n\n${body.trim()}\n\n使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。\n`
    );
    written.push(skillPath);
  }
  return written;
}

module.exports = { generateSkillsFromCommands, parseCommand };
