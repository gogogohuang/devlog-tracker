---
description: 讀取具名保存的 devlog，依最後一輪 Handoff 接續該段工作。
---

取得使用者提供的 `<name>`；沒有名稱時先詢問。跑：

```bash
先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/resume-devlog.sh" --name "<name>"
```
```

若回傳 `MISSING`，列出 `CANDIDATES` 讓使用者選，不要自動執行工作。
找到檔案後，像 `/devlog-tracker:continue` 一樣讀最後一個歷史 Round：
`IN_PROGRESS` 時依 Handoff 的「下一步」提出接續方式。等待使用者確認後才開工。

後續紀錄一律寫進 `.devlog/devlog.md`，不要改寫具名 keep 檔。
