---
description: 暫停這個專案的 devlog 強制記錄機制。不會刪除任何歷史紀錄，只是之後 Stop 與 PreToolUse hook 都因 `.enabled` 移除而停止檢查。
---

請執行：

1. 跑：
   ```bash
   先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/pause-devlog.sh"
```
   ```
   不要自己刪 `.enabled`。
2. stdout 是 `NOT_ENABLED`：告知這個專案本來就沒有啟動強制記錄，結束。
3. stdout 是 `PAUSED`：告知強制記錄已暫停，歷史都還在，可用 `/devlog-tracker:start` 再開。

不要動 `.devlog/devlog.md`、`.checkpoint-state`、`.segment-state`。
