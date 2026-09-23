'use strict';
const path = require('path');
const { mergeHooksTemplate } = require('../merge-hooks');
const { upsertMarkdown, BEGIN, END } = require('../agents-md');
const { generateSkillsFromCommands } = require('../skills-from-commands');

function claudeBlock() {
  return `${BEGIN}
## devlog-tracker

這個專案用 devlog-tracker 在 \`.devlog/devlog.md\` 維護逐輪紀錄。指令是 \`.claude/skills/devlog-<名稱>/\` 底下的 skill，用 \`/devlog-<名稱>\` 執行；若 skill 不可用，請照下面對照做：

1. 先 \`source .devlog-tracker/env.sh\`（設定 \`DEVLOG_TRACKER_ROOT\`）。
2. 依使用者意圖讀對應的 \`.devlog-tracker/commands/<名稱>.md\`，照裡面的步驟做（腳本在 \`.devlog-tracker/core/scripts/\`，執行時 \`DEVLOG_PROJECT_DIR\` 設成專案根目錄）。

| 使用者說 | 讀這份 |
|---|---|
| 開始追蹤 / start | \`/devlog-start\`；\`commands/start.md\` |
| 暫停 / pause | \`/devlog-pause\`；\`commands/pause.md\` |
| 狀態 / status | \`/devlog-status\`；\`commands/status.md\` |
| 接續上一題 / continue（換過工具或 \`/clear\` 之後） | \`commands/continue.md\` |
| 歸檔 / compact | \`commands/compact.md\` |
| 清空重編 / clean（不可復原，先問使用者確認） | \`commands/clean.md\` |
| 保存主題 / keep、接續具名檔 / resume、跨主題總覽 / overview | \`commands/keep.md\`、\`commands/resume.md\`、\`commands/overview.md\` |
| 沉澱規範寫進 CLAUDE.md／AGENTS.md / promote | \`commands/promote.md\` |
| 統計 / report、HTML 時間軸 / timeline | \`commands/report.md\`、\`commands/timeline.md\` |
| 產生 PR 描述 / pr | \`commands/pr.md\` |
| 長任務定期記錄 / span | \`commands/span.md\` |
| 調整沉默門檻 / checkpoint、segment-watch | \`commands/checkpoint.md\`、\`commands/segment-watch.md\` |
| 開發歷程教訓 / lessons、lessons-on、lessons-off、lessons-drift | \`commands/lessons.md\`、\`commands/lessons-on.md\`、\`commands/lessons-off.md\`、\`commands/lessons-drift.md\` |

寫 devlog 的格式與規則見 \`.devlog-tracker/skills/devlog-tracker/SKILL.md\`。每輪結束前必須把當輪寫進 \`.devlog/\`；已 \`start\` 的專案，Stop hook 會擋沒寫完的輪次。

注意：若同時透過 Claude Code plugin marketplace 安裝了 devlog-tracker，這兩條安裝路線的 hook 都會生效，導致同一輪被記錄兩次；二選一即可。
${END}
`;
}

function installSkills({ targetDir, vendorRoot }) {
  generateSkillsFromCommands({
    commandsDir: path.join(vendorRoot, 'commands'),
    targetSkillsDir: path.join(targetDir, '.claude', 'skills'),
    namePrefix: 'devlog',
  });
}

function install({ repoRoot, targetDir, vendorRoot }) {
  mergeHooksTemplate({
    templatePath: path.join(repoRoot, 'claude', 'hooks.json'),
    targetPath: path.join(targetDir, '.claude', 'settings.local.json'),
    vendorRoot,
    placeholders: ['${DEVLOG_TRACKER_ROOT}', '${CLAUDE_PLUGIN_ROOT}'],
  });
  installSkills({ targetDir, vendorRoot });
  upsertMarkdown(targetDir, { fileName: 'CLAUDE.md', block: claudeBlock() });
}

module.exports = { install, installSkills };
