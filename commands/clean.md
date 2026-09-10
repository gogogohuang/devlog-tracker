---
description: 無條件清空 .devlog/devlog.md（含專案摘要與所有 Round 歷史），只留這一輪重編成 Round 1；不可復原，執行前一定要先問使用者確認
---

請執行 devlog clean（無條件清空）。這是使用者主動執行 `/devlog-tracker:clean` 時才做的事，不要自動觸發。

確認之前不要跑清空腳本、不要動 `devlog.md` 的既有歷史內容。這一輪本身仍照 devlog-tracker 的一般規則：結束前要補 `### Summary` / `### Handoff` / `### Status`（Status 通常是 `BLOCKED`，因為在等使用者回覆）——這跟「先問再等」不衝突，Stop hook 檢查的是這一輪有沒有收尾，不是有沒有清空。

## 1. 讀檔

讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知「目前沒有東西可清空」，不要建立 `.devlog/` 或任何新檔，結束。

## 2. 先問，然後停下來等

數一下檔案裡有幾個 `## Round`（判斷標題時，略過圍欄程式碼區塊 ``` 內的行，與 hook 腳本解析方式一致）。用這一則訊息問：

```
這個動作會把 .devlog/devlog.md 整份清空（含專案摘要與全部 <N> 個 Round 歷史），
不可復原、不會搬移或備份到別的檔案（devlog.archive.md、devlog.<name>.md 具名保存檔
都不受影響，如果想先保留這份的內容，改用 /devlog-tracker:keep）。
清空同時也會關閉 Span Mode（刪 .span-open）、把 checkpoint 計數歸零。
確定要清空，請回覆「清空」；其他任何回覆都當作取消。
```

這一輪照上面的規則正常收尾（Summary 記下「詢問是否清空，等待回覆」，Status 用 `BLOCKED`），然後停止。

- 回覆不是「清空」（含沒回覆、模糊、其他任何字）→ 不跑腳本、不改 `devlog.md`，告知已取消，這一輪（或折入/新開的這一輪）收尾即可，結束。
- 回覆「清空」→ 進入步驟 3。

## 3. 跑清空腳本

```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/clean-devlog.sh" --confirmed
```

`--confirmed` 是必要參數，只有在使用者明確回覆「清空」之後才可以帶這個參數執行；不要在其他情況下跑這支腳本。腳本是唯一的實作來源：有沒有開著的 Round、要重編成 Round 1 還是整份刪除、重置 `.span-open` 與 checkpoint 狀態，都不要自己動手做。exit 1 時原樣顯示 stderr，不要自行重試、不要自己動手改檔案。

## 4. 處理結果並收尾這一輪

依 stdout 的 `KEPT_ROUND`：

- `KEPT_ROUND=1`：告知已清空，這一輪重編成 `## Round 1`。這一輪結束前補上（或改寫）`### Summary`（記下這次清空的結果）/ `### Handoff` / `### Status`（Stop hook 仍會檢查）。
- `KEPT_ROUND=0`：告知已整份清空。若 `.devlog/.enabled` 存在，說下一則訊息會重新從 Round 1 開始記錄；若不存在（強制記錄目前是暫停或從未啟動），說清楚要先 `/devlog-tracker:start` 才會開始新的 Round 1。沒有輪次可補收尾。

不要讀寫 `devlog.archive.md` 或任何 `.devlog/devlog.<name>.md` 具名檔。
