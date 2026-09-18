'use strict';
const fs = require('fs');
const path = require('path');

const BEGIN = '<!-- devlog-tracker:begin -->';
const END = '<!-- devlog-tracker:end -->';

const BLOCK = `${BEGIN}
## devlog-tracker

這個專案用 devlog-tracker 在 \`.devlog/devlog.md\` 維護逐輪紀錄（Claude Code 與 Codex 共用同一份）。Codex 沒有 \`/devlog-tracker:*\` slash 指令，請照下面對照做：

1. 先 \`source .devlog-tracker/env.sh\`（設定 \`DEVLOG_TRACKER_ROOT\`）。
2. 依使用者意圖讀對應的 \`.devlog-tracker/commands/<名稱>.md\`，照裡面的步驟做（腳本在 \`.devlog-tracker/hooks/scripts/\`，執行時 \`CLAUDE_PROJECT_DIR\` 設成專案根目錄）。

| 使用者說 | 讀這份 |
|---|---|
| 開始追蹤 / start | \`commands/start.md\` |
| 接續上一題 / continue（換過工具或 \`/clear\` 之後） | \`commands/continue.md\` |
| 暫停 / pause | \`commands/pause.md\` |
| 狀態 / status | \`commands/status.md\` |
| 歸檔 / compact | \`commands/compact.md\` |
| 保存主題 / keep、接續具名檔 / resume | \`commands/keep.md\`、\`commands/resume.md\` |

寫 devlog 的格式與規則見 \`.devlog-tracker/skills/devlog-tracker/SKILL.md\`。每輪結束前必須把當輪寫進 \`.devlog/\`；已 \`start\` 的專案，Stop hook 會擋沒寫完的輪次。
${END}
`;

function upsertAgentsMd(targetDir) {
  const filePath = path.join(targetDir, 'AGENTS.md');
  const existing = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
  const begin = existing.indexOf(BEGIN);
  const end = existing.indexOf(END);

  let next;
  if (begin !== -1 && end > begin) {
    next = existing.slice(0, begin) + BLOCK + existing.slice(end + END.length).replace(/^\n/, '');
  } else if (existing.trim() === '') {
    next = BLOCK;
  } else {
    next = `${existing.replace(/\n*$/, '\n')}\n${BLOCK}`;
  }
  if (next !== existing) fs.writeFileSync(filePath, next);
  return filePath;
}

module.exports = { upsertAgentsMd, BEGIN, END };
