---
description: 在 devlog.md／archive／keep 檔／lessons 檔裡搜尋關鍵字，列出命中的檔案、標題與行內容（純讀取，不核對工作區、不等確認）。
---

取得使用者提供的 `<關鍵字>`；沒有給的話先問。這是純讀取，不做 `commands/continue.md`／`commands/resume.md` 那套「核對工作區、等確認才動手」流程——搜尋結果是導航用的參考，不是暫停中的工作主題。讀完之後不要自動據此修改任何檔案，除非使用者接著明確要求。

記下你目前已經確認的專案根目錄絕對路徑（後面步驟都要用這個值，不要用 `$(pwd)` 重新推——理由同 `commands/continue.md` 步驟 1）。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<剛才記下的專案根目錄絕對路徑>" bash "${PLUGIN_ROOT}/core/scripts/search-devlog.sh" "<關鍵字>"
```

這支腳本會掃過 `.devlog/devlog*.md`（含 `devlog.md`、`devlog.archive.md`、已 keep 的 `devlog.<name>.md`、`devlog.lessons.<topic>.md`，以及分支各自的 `devlog.<branch>.md`——一個 glob 涵蓋所有種類，不分別處理），做不分大小寫的字串比對，不是正則、不含 vector/LLM。

- `NO_INDEX`：告知目前還沒有任何 devlog 檔案，結束。
- `NO_MATCH`：告知這個關鍵字沒有命中，結束。
- 其他輸出：每個有命中的檔案先印一行 `FILE=.devlog/<檔名>`，接著是該檔案裡每一行命中，格式 `HEADING="<離命中最近的上方 ## 或 ### 標題>" LINE=<行號>: <命中行原文>`。依檔案分組原樣顯示給使用者，不用額外解讀或摘要——這是導航用的搜尋結果列表，不是知識庫總覽（跟 `/devlog-tracker:overview` 不同）。提醒使用者可以用 `/devlog-tracker:resume <name>` 或 `/devlog-tracker:lessons <topic>` 進一步查看命中的具名檔全文。

標題比對不是圍欄感知的（不特別處理 ``` 區塊），命中或標題落在程式碼區塊裡時仍會照樣列出；這是刻意的簡化，換取不用重新實作 `devlog-md.sh` 的圍欄邏輯。
