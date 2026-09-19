'use strict';
const fs = require('fs');
const path = require('path');
const { mergeHooksTemplate } = require('../merge-hooks');
const { upsertAgentsMd } = require('../agents-md');

// Codex 只從 ~/.codex/prompts/ 讀 custom prompts（且已棄用），不會讀專案內的
// .codex/prompts/；專案層級的指令要做成 .agents/skills/<name>/SKILL.md，以 $<name> 叫用。
function parseCommand(text) {
  const match = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(text);
  if (!match) return { description: '', body: text };
  const description = /^description:\s*(.*)$/m.exec(match[1]);
  return { description: description ? description[1].trim() : '', body: match[2] };
}

// 0.25.0 曾把 prompts 寫到 .codex/prompts/devlog-*.md，Codex 讀不到；升級時清掉。
function removeLegacyPrompts(targetDir) {
  const promptsDir = path.join(targetDir, '.codex', 'prompts');
  if (!fs.existsSync(promptsDir)) return;
  for (const file of fs.readdirSync(promptsDir)) {
    if (/^devlog-.*\.md$/.test(file)) fs.rmSync(path.join(promptsDir, file));
  }
  if (fs.readdirSync(promptsDir).length === 0) fs.rmdirSync(promptsDir);
}

function installSkills({ targetDir, vendorRoot }) {
  const commandsDir = path.join(vendorRoot, 'commands');
  for (const file of fs.readdirSync(commandsDir)) {
    if (!file.endsWith('.md')) continue;
    const name = `devlog-${path.basename(file, '.md')}`;
    const { description, body } = parseCommand(fs.readFileSync(path.join(commandsDir, file), 'utf8'));
    const skillDir = path.join(targetDir, '.agents', 'skills', name);
    fs.mkdirSync(skillDir, { recursive: true });
    fs.writeFileSync(
      path.join(skillDir, 'SKILL.md'),
      `---\nname: ${name}\ndescription: ${JSON.stringify(description)}\n---\n\n${body.trim()}\n\n使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。\n`
    );
  }
  removeLegacyPrompts(targetDir);
}

function install({ repoRoot, targetDir, vendorRoot }) {
  mergeHooksTemplate({
    templatePath: path.join(repoRoot, 'codex', 'hooks.json'),
    targetPath: path.join(targetDir, '.codex', 'hooks.json'),
    vendorRoot,
  });
  installSkills({ targetDir, vendorRoot });
  upsertAgentsMd(targetDir);
}

module.exports = { install, installSkills };
