---
name: devlog-search
description: "在 devlog.md／archive／keep 檔／lessons 檔裡搜尋關鍵字，讀完命中後用自己的話回答（純讀取，不核對工作區、不等確認）。"
---

Codex plugin 安裝：目前這份 `SKILL.md` 的絕對路徑位於
`<plugin 根目錄>/codex/skills/<skill 名稱>/SKILL.md`。每次用 shell 執行下方步驟時，
先從這份檔案的所在目錄往上三層取得 plugin 根目錄，並在同一次 shell 呼叫中
`export DEVLOG_TRACKER_ROOT="<該根目錄的絕對路徑>"`。
一般 shell 呼叫不一定有 hook 專用的 `PLUGIN_ROOT`／`CLAUDE_PLUGIN_ROOT` 環境變數。
若是 npx 安裝，沿用專案內既有的 `DEVLOG_TRACKER_ROOT`。

取得使用者提供的 `<關鍵字>`（或自然語言查詢裡的關鍵片語）；沒有給的話先問。這是純讀取，不做 `commands/continue.md`／`commands/resume.md` 那套「核對工作區、等確認才動手」流程——搜尋結果是導航用的參考，不是暫停中的工作主題。讀完之後不要自動據此修改任何檔案，除非使用者接著明確要求。

記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1）。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<剛才記下的專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/search-devlog.sh" "<關鍵字>"
```

這支腳本會掃過 `.devlog/devlog*.md`（含 `devlog.md`、`devlog.archive.md`、已 keep 的 `devlog.<name>.md`、`devlog.lessons.<topic>.md`，以及分支各自的 `devlog.<branch>.md`——一個 glob 涵蓋所有種類，不分別處理），做不分大小寫的字串比對，不是正則、不含 vector/LLM。自然語言查詢由你先抽出要搜的關鍵片語再丟給腳本；腳本本身不做 NLP。

- `NO_INDEX`：告知目前還沒有任何 devlog 檔案，結束。
- `NO_MATCH`：告知這個關鍵字沒有命中，結束。
- 其他輸出：每個有命中的檔案先印一行 `FILE=.devlog/<檔名>`，接著是該檔案裡每一行命中，格式 `HEADING="<離命中最近的上方 ## 或 ### 標題>" LINE=<行號>: <命中行原文>`。

**回答姿勢（跟 `/devlog-tracker:overview` 不同，也跟「原樣貼出列表」不同）：** 讀完腳本輸出後，用自己的話回答使用者在問什麼（決策、現況、誰提過什麼），把命中當依據串成敘事；必要時附上檔名、最近標題、行號當出處。不要把 `FILE=`／`HEADING=` 原始輸出整段貼給使用者當主回答。命中很多時先摘要再說細節，不要機械 dump。若命中落在具名檔或 lessons 檔，可提醒再用 `/devlog-tracker:resume <name>` 或 `/devlog-tracker:lessons <topic>` 看全文。

標題比對不是圍欄感知的（不特別處理 ``` 區塊），命中或標題落在程式碼區塊裡時仍會照樣列出；這是刻意的簡化，換取不用重新實作 `devlog-md.sh` 的圍欄邏輯。

使用者提供的額外參數：請看觸發這個 skill 的使用者訊息。
