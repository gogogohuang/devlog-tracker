---
name: devlog-resume
description: "讀取具名保存的 devlog，核對最後一輪 Handoff 工作區後再接續該段工作。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

取得使用者提供的 `<name>`；沒有名稱時先詢問。記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1：Bash 工具的工作目錄會在對話裡持續累積前面呼叫的 `cd`，用當下的 `pwd` 可能已經不是這個專案根目錄）。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<剛才記下的專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/resume-devlog.sh" --name "<name>"
```

若回傳 `MISSING`，列出 `CANDIDATES` 讓使用者選，不要自動執行工作。
找到檔案後，讀最後一個歷史 Round。`DONE`：告訴使用者該主題已結束，等新需求。不核對、不開工。
`IN_PROGRESS`、`INTERRUPTED`、`BLOCKED`：先做 `commands/continue.md` **步驟 5.1–5.2**（沿用上面同一個專案根目錄絕對路徑，不要重新推；不要跟著做 5.3）。步驟 5.2 的 `### 段落` 寫進 `devlog.md` 的 open Round，不要寫進 keep 檔。然後依核對後的**實際工作樹**提出接續方式，**等待使用者確認後才做下一步**：
- `IN_PROGRESS`／`INTERRUPTED`：提出 Handoff 的下一步（`<next>`；舊格式 `#### 下一步`）（沒有就依現況（`<state>`；舊格式 `#### 現況`）與實際工作樹推）。
- `BLOCKED`：說明缺什麼；缺的外部輸入已經出現就提出下一步，仍缺就停。git 相不相符不能證明缺件已到，不要發明輸入。

後續紀錄一律寫進 `.devlog/devlog.md`，不要改寫具名 keep 檔。使用者確認並開工後，**同一輪必須收尾寫回** Summary／Reply／Handoff／Status（L1 寫回義務同 `commands/continue.md` 步驟 6）。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
