---
description: 無條件清空 .devlog/devlog.md（含專案摘要與所有 Round 歷史），只留這一輪重編成 Round 1；不可復原，執行前一定要先問使用者確認
---

請執行 devlog clean（無條件清空）。這是使用者主動執行 `/devlog-tracker:clean` 時才做的事，不要自動觸發。

確認之前不要寫任何檔。

## 1. 讀檔

讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知「目前沒有東西可清空」，不要建立 `.devlog/` 或任何新檔，結束。

## 2. 先問，然後停下來等

數一下檔案裡有幾個 `## Round`（判斷標題時，略過圍欄程式碼區塊 ``` 內的行，與 hook 腳本解析方式一致）。用這一則訊息問：

```
這個動作會把 .devlog/devlog.md 整份清空（含專案摘要與全部 N 個 Round 歷史），
不可復原、不會搬移或備份到別的檔案（如果想先保留，改用 /devlog-tracker:keep）。
確定要清空，請回覆「清空」；其他任何回覆都當作取消。
```

然後停止。使用者還沒回覆前不要寫任何檔。

- 回覆不是「清空」（含沒回覆、模糊、其他任何字）→ 不改檔，告知已取消，結束。
- 回覆「清空」→ 進入步驟 3。

## 3. 跑清空腳本

```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/clean-devlog.sh"
```

腳本是唯一的實作來源：有沒有開著的 Round、要重編成 Round 1 還是整份刪除、重置 `.span-open` 與 checkpoint 狀態，都不要自己動手做。exit 1 時原樣顯示 stderr，不要自行重試。

## 4. 處理結果並收尾這一輪

依 stdout 的 `KEPT_ROUND`：

- `KEPT_ROUND=1`：告知已清空，這一輪重編成 `## Round 1`。這一輪結束前仍要照舊補 `### Summary` / `### Handoff` / `### Status`（Stop hook 仍會檢查）。
- `KEPT_ROUND=0`：告知已整份清空，下一則訊息會重新從 Round 1 開始記錄。沒有輪次可補收尾。

不要讀寫 `devlog.archive.md` 或任何 `.devlog/devlog.<name>.md` 具名檔。
