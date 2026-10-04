---
description: 停用目標專案的 SessionStart devlog context。
---

請執行：

1. 確認目標專案根目錄的絕對路徑。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：
   ```bash
   PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
   DEVLOG_PROJECT_DIR="<已確認的專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/session-context-off.sh"
   ```
   若兩個環境變數都空，先將 `PLUGIN_ROOT` 設為上述本 plugin 根目錄的絕對路徑。不要自己建立開關檔案。
2. 腳本成功且 stdout 是 `SESSION_CONTEXT_DISABLED`：告知目標專案已停用 SessionStart devlog context，下次 Claude Code、Codex 或 Cursor SessionStart 生效。此指令只寫入專案根目錄的 `.devlog-session-context`，不修改 `.devlog` 紀錄。
3. 腳本失敗：回報錯誤，不要宣稱已停用。`DEVLOG_PROJECT_DIR` 必須是存在的絕對目錄，不會回退到目前工作目錄或 `CLAUDE_PROJECT_DIR`。
