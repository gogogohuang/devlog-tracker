---
description: 讀取具名保存的 devlog，核對最後一輪 Handoff 工作區後再接續該段工作。
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
找到檔案後，讀最後一個歷史 Round。`DONE`：告訴使用者該主題已結束，等新需求。不核對、不開工。
`IN_PROGRESS`、`INTERRUPTED`、`BLOCKED`：先做 `commands/continue.md` **步驟 5.1–5.2** 的工作區核對（不要跟著做 5.3 的立刻開工）。有 `#### 工作區` 但跟實際不符時，在**這一輪**（寫進 `devlog.md` 的 open Round）追加一段 `### 段落`（宣稱 vs 實際）；沒有這一節（舊 Round、`INTERRUPTED` stub）就沒有宣稱可對，不用寫 `### 段落`。然後依核對後的**實際工作樹**提出接續方式，**等待使用者確認後才做下一步**：
- `IN_PROGRESS`／`INTERRUPTED`：提出 Handoff「下一步」（沒有就依「現況」與實際工作樹推）。
- `BLOCKED`：說明缺什麼；缺的外部輸入已經出現就提出下一步，仍缺就停。git 相不相符不能證明缺件已到，不要發明輸入。

後續紀錄一律寫進 `.devlog/devlog.md`，不要改寫具名 keep 檔。
