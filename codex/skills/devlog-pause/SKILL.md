---
name: devlog-pause
description: "暫停這個專案的 devlog 強制記錄機制。不會刪除任何歷史紀錄，只是之後 Stop 與 PreToolUse hook 都因 `.enabled` 移除而停止檢查。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

請執行：

1. 跑：
   ```bash
   先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/pause-devlog.sh"
```
   ```
   不要自己刪 `.enabled`。
2. stdout 是 `NOT_ENABLED`：告知這個專案本來就沒有啟動強制記錄，結束。
3. stdout 是 `PAUSED`：告知強制記錄已暫停，歷史都還在，可用 `/devlog-tracker:start` 再開。

不要動 `.devlog/devlog.md`、`.checkpoint-state`、`.segment-state`。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
