---
description: 關閉 Lessons Mode。不會刪除任何已寫的 devlog.lessons.*.md 或索引，只是之後不再考慮記新的一筆。
---

請執行：

1. 先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：
   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
   CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/lessons-off.sh"
   ```
   不要自己刪 `.lessons-enabled`。
2. stdout 是 `NOT_ENABLED`：告知 Lessons Mode 本來就沒開，結束。
3. stdout 是 `LESSONS_DISABLED`：告知已關閉，歷史教訓都還在（`devlog.lessons.*.md` 與 `## Lessons 索引`），可用 `/devlog-tracker:lessons-on` 再開。

不要動任何 `devlog.lessons.*.md`、`## Lessons 索引`，也不要動 `.devlog/.enabled`（那是主開關，不受這個指令影響）。
