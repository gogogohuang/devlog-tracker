'use strict';
const fs = require('fs');
const path = require('path');
const { mergeHooksTemplate } = require('../merge-hooks');
const { upsertAgentsMd } = require('../agents-md');
const { generateSkillsFromCommands } = require('../skills-from-commands');

// Codex 只從 ~/.codex/prompts/ 讀 custom prompts（且已棄用），不會讀專案內的
// .codex/prompts/；專案層級的指令要做成 .agents/skills/<name>/SKILL.md，以 $<name> 叫用。

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
  generateSkillsFromCommands({
    commandsDir: path.join(vendorRoot, 'commands'),
    targetSkillsDir: path.join(targetDir, '.agents', 'skills'),
    namePrefix: 'devlog',
  });
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
