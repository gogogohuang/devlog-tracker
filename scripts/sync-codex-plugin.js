#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { parseCommand } = require('../cli/skills-from-commands');

const PLUGIN_ROOT_GUIDANCE = `Codex plugin 安裝：目前這份 \`SKILL.md\` 的絕對路徑位於
\`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md\`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
\`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"\`。
一般 shell 呼叫不一定有 hook 專用的 \`PLUGIN_ROOT\`／\`CLAUDE_PLUGIN_ROOT\` 環境變數。
若是 npx 安裝，沿用專案內既有的 \`DEVLOG_TRACKER_ROOT\`。\n\n`;

function withPluginRootGuidance(skill) {
  const frontmatter = /^---\n[\s\S]*?\n---\n\n?/.exec(skill);
  if (!frontmatter) throw new Error('Codex skill is missing frontmatter');
  return frontmatter[0] + PLUGIN_ROOT_GUIDANCE + skill.slice(frontmatter[0].length);
}

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
    const skill =
      `---\nname: ${name}\ndescription: ${JSON.stringify(description)}\n---\n\n${body.trim()}\n\n使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。\n`;
    files.set(
      `codex/skills/${name}/SKILL.md`,
      withPluginRootGuidance(skill)
    );
  }

  const sourceSkillsDir = path.join(root, 'skills', 'devlog-tracker');
  for (const source of walkFiles(sourceSkillsDir)) {
    const relative = path.relative(path.join(root, 'skills'), source);
    let content = fs.readFileSync(source, 'utf8');
    if (relative === path.join('devlog-tracker', 'SKILL.md')) {
      content = content.replace(
        /^description:.*$/m,
        'description: 在 Codex 專案維護 .devlog/devlog.md 逐輪紀錄；使用 $devlog-start 開始，$devlog-continue 接續。當使用者提到 devlog-tracker、.devlog/devlog.md 或明確要寫／接續紀錄時使用。'
      );
    }
    files.set(path.join('codex', 'skills', relative),
      path.basename(relative) === 'SKILL.md' ? withPluginRootGuidance(content) : content);
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
