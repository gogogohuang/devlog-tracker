---
name: devlog-lessons-off
description: "關閉 Lessons Mode。不會刪除任何已寫的 devlog.lessons.*.md 或索引，只是之後不再考慮記新的一筆。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

請執行：

1. 先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：
   ```bash
   PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
   DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/lessons-off.sh"
   ```
   不要自己刪 `.lessons-enabled`。
2. stdout 是 `NOT_ENABLED`：告知 Lessons Mode 本來就沒開，結束。
3. stdout 是 `LESSONS_DISABLED`：告知已關閉，歷史教訓都還在（`devlog.lessons.*.md` 與 `## Lessons 索引`），可用 `/devlog-tracker:lessons-on` 再開。

不要動任何 `devlog.lessons.*.md`、`## Lessons 索引`，也不要動 `.devlog/.enabled`（那是主開關，不受這個指令影響）。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
