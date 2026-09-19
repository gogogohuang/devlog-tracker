'use strict';
const fs = require('fs');
const path = require('path');
const { mergeHooksTemplate } = require('../merge-hooks');
const { upsertAgentsMd } = require('../agents-md');

function installPrompts({ targetDir, vendorRoot }) {
  const commandsDir = path.join(vendorRoot, 'commands');
  const promptsDir = path.join(targetDir, '.codex', 'prompts');
  fs.mkdirSync(promptsDir, { recursive: true });
  for (const file of fs.readdirSync(commandsDir)) {
    if (!file.endsWith('.md')) continue;
    const command = path.basename(file, '.md');
    const source = path.join(commandsDir, file);
    const destination = path.join(promptsDir, `devlog-${command}.md`);
    fs.writeFileSync(
      destination,
      `${fs.readFileSync(source, 'utf8').trimEnd()}\n\n使用者提供的額外參數：$ARGUMENTS\n`
    );
  }
}

function install({ repoRoot, targetDir, vendorRoot }) {
  mergeHooksTemplate({
    templatePath: path.join(repoRoot, 'codex', 'hooks.json'),
    targetPath: path.join(targetDir, '.codex', 'hooks.json'),
    vendorRoot,
  });
  installPrompts({ targetDir, vendorRoot });
  upsertAgentsMd(targetDir);
}

module.exports = { install, installPrompts };
