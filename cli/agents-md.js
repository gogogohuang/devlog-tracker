'use strict';
const fs = require('fs');
const path = require('path');

const BEGIN = '<!-- devlog-tracker:begin -->';
const END = '<!-- devlog-tracker:end -->';

function codexBlock() {
  return `${BEGIN}
## devlog-tracker

這個專案用 devlog-tracker 在 \`.devlog/devlog.md\` 維護逐輪紀錄（Claude Code 與 Codex 共用同一份）。Codex 指令是 \`.agents/skills/devlog-<名稱>/\` 底下的 skill，用 \`/skills\` 選或打 \`$devlog-<名稱>\` 執行；若 skill 不可用，請照下面對照做：

1. 先 \`source .devlog-tracker/env.sh\`（設定 \`DEVLOG_TRACKER_ROOT\`）。
2. 依使用者意圖讀對應的 \`.devlog-tracker/commands/<名稱>.md\`，照裡面的步驟做（腳本在 \`.devlog-tracker/core/scripts/\`，執行時 \`DEVLOG_PROJECT_DIR\` 設成專案根目錄）。

| 使用者說 | 讀這份 |
|---|---|
| 開始追蹤 / start | \`$devlog-start\`；\`commands/start.md\` |
| 暫停 / pause | \`$devlog-pause\`；\`commands/pause.md\` |
| 狀態 / status | \`$devlog-status\`；\`commands/status.md\` |
| 接續上一題 / continue（換過工具或 \`/clear\` 之後） | \`commands/continue.md\` |
| 歸檔 / compact | \`commands/compact.md\` |
| 清空重編 / clean（不可復原，先問使用者確認） | \`commands/clean.md\` |
| 保存主題 / keep、接續具名檔 / resume、跨主題總覽 / overview | \`commands/keep.md\`、\`commands/resume.md\`、\`commands/overview.md\` |
| 沉澱規範寫進 CLAUDE.md／AGENTS.md / promote | \`commands/promote.md\` |
| 搜尋 / search | \`commands/search.md\` |
| 統計 / report、HTML 時間軸 / timeline | \`commands/report.md\`、\`commands/timeline.md\` |
| 產生 PR 描述 / pr | \`commands/pr.md\` |
| 長任務定期記錄 / span | \`commands/span.md\` |
| 調整沉默門檻 / checkpoint、segment-watch | \`commands/checkpoint.md\`、\`commands/segment-watch.md\` |
| 開發歷程教訓 / lessons、lessons-on、lessons-off、lessons-drift | \`commands/lessons.md\`、\`commands/lessons-on.md\`、\`commands/lessons-off.md\`、\`commands/lessons-drift.md\` |

寫 devlog 的格式與規則見 \`.devlog-tracker/skills/devlog-tracker/SKILL.md\`。每輪結束前必須把當輪寫進 \`.devlog/\`；已 \`start\` 的專案，Stop hook 會擋沒寫完的輪次。
${END}
`;
}

function upsertMarkdown(targetDir, { fileName = 'AGENTS.md', block = codexBlock() } = {}) {
  const filePath = path.join(targetDir, fileName);
  const existing = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
  const begin = existing.indexOf(BEGIN);
  const end = existing.indexOf(END);

  let next;
  if (begin !== -1 && end > begin) {
    next = existing.slice(0, begin) + block + existing.slice(end + END.length).replace(/^\n/, '');
  } else if (existing.trim() === '') {
    next = block;
  } else {
    next = `${existing.replace(/\n*$/, '\n')}\n${block}`;
  }
  if (next !== existing) fs.writeFileSync(filePath, next);
  return filePath;
}

function upsertAgentsMd(targetDir) {
  return upsertMarkdown(targetDir, { fileName: 'AGENTS.md', block: codexBlock() });
}

module.exports = { upsertAgentsMd, upsertMarkdown, codexBlock, BEGIN, END };
