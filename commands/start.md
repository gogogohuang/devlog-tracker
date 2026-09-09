---
description: 啟動這個專案的 devlog 強制記錄機制。之後每一輪結束前都會被 Stop hook 檢查，沒寫 devlog 就不能結束。
---

請執行以下步驟：

1. 跑這支腳本（環境變數 `CLAUDE_PLUGIN_ROOT` 若有值就用它；否則用這個 plugin 根目錄，也就是含 `.claude-plugin/plugin.json` 的那一層）：
   ```bash
   CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/start-devlog.sh"
   ```
   不要自己用手建 `.enabled` / `.checkpoint-state` / `.segment-state`。
2. 若 stdout 有 `GITIGNORE_DEVLOG=no`：告訴使用者 `.devlog/` 會含 prompt，建議把 `.devlog/` 加進專案 `.gitignore`。問要不要現在加。只有使用者明確說要，才在 `.gitignore` 末尾追加一行 `.devlog/`（檔案不存在就建立）。不要改其他行。
3. 讀取 `.devlog/devlog.md`（若存在）：
   - 有內容：摘要目前進度，跟使用者確認「上次做到哪、狀態是什麼」
   - 不存在：告知使用者這是全新開始，準備寫下 Round 1
4. 告訴使用者：從現在開始，每一則使用者訊息送出時就會先寫 User Input skeleton，結束前仍要補 Summary / Handoff；同一輪約 15 分鐘沒改這個檔，下一個工具會被要求先補 `### 段落`；可以用 `/devlog-tracker:pause` 關掉。

不要因為 `.enabled` 已經存在就跳過步驟 3。`/clear` 之後若要接著做上一題，用 `/devlog-tracker:continue`，不要用 start 開工。
