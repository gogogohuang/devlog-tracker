---
name: devlog-session-context-off
description: "停用本專案 SessionStart 注入的 devlog-tracker context。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

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

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
