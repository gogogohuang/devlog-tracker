---
description: 停用本專案 SessionStart 注入的 devlog-tracker context。
---

請執行：

1. 先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），並確認目標專案根目錄的絕對路徑：
   ```bash
   PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
   DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/session-context-off.sh"
   ```
   不要用 `$(pwd)` 推測目標專案，也不要自行建立或改寫 `.devlog`。
2. stdout 是 `SESSION_CONTEXT_DISABLED`：告知已停用這個專案的 devlog-tracker SessionStart context。下次啟動 Claude Code、Codex 或 Cursor 時，該 hook 不會注入 context。
3. 若腳本失敗，告知使用者需提供存在的專案根目錄絕對路徑，再重試。

此指令只把目標專案根目錄的 `.devlog-session-context` 寫成精確的 `off`（不含換行）。
