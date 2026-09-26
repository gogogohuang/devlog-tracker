---
name: devlog-span
description: "開啟或關閉 Span Mode，讓自動續接的長任務定期記錄進度。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

先判斷使用者要開啟或關閉：

- 使用者明確要求關閉，或 `.devlog/.span-open` 已存在且沒有明確要求重新開啟：
  先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），設 `PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"`，再跑 `DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/span-close.sh"`，
  再依 SKILL 的 span 收尾規則寫一個**新的 Round**，總結整段 span。
- 使用者要求開啟：先把目前 Round 正常寫完，`Status` 設為 `IN_PROGRESS`，再跑
  `DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/span-open.sh"`。

不要手寫 `.span-open` JSON。腳本 exit 1 時顯示 stderr，停止操作。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
