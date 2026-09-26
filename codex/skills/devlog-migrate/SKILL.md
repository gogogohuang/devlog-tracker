---
name: devlog-migrate
description: "把 .devlog 裡舊格式（#### 小節）的 Handoff／Session Handoff 轉成 XML 標籤格式；Stop hook 擋下舊格式時也會叫 agent 跑它"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

請執行 Handoff 格式遷移：

1. 決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），然後跑（不要自己改檔）：
   ```bash
   PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
   DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/migrate-handoff.sh"
   ```
2. 依 stdout 回報一句話：
   - `NO_DEVLOG`：這個專案沒有 `.devlog/`，沒有東西要轉。
   - `LOCKED <pid>`：另一個 session 正在寫 devlog，稍後再跑一次。
   - 否則用 `MIGRATED=` 與 `SKIPPED=` 回報轉了幾輪、跳過幾輪；`BACKUP=` 是轉換前的備份。
3. 有 `SKIP ... Round <N>: <原因>` 時：歷史輪次保留原樣即可（讀取端相容舊格式）。只有**這一輪**（開著的 `.round-current.md`）被跳過時，才照 `skills/devlog-tracker/SKILL.md`「每一輪的紀錄格式」的 XML 模板手動改寫這一輪的 Handoff／Session Handoff。

只轉 `.round-current.md`、`devlog.md`、branch 檔（首行是 `<!-- devlog-origin: ... -->`）與 `handoff*.md`；不轉 `devlog.archive.md`、keep 產生的具名檔、lessons 檔。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
