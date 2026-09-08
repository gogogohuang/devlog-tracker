---
description: 把 .devlog/devlog.md 裡已完成且較舊的紀錄搬到 devlog.archive.md，避免主檔案無限膨脹
---

請執行 devlog 壓縮：

1. 讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知使用者目前沒有東西可壓縮，不要建立空檔案，結束。
2. 找出所有 `## Round <N>` 區塊，判斷各自的 Status。
3. 保留規則（以下皆保留在 devlog.md，不搬動）：
   - 檔案開頭的專案摘要（如果有）
   - 最近 5 輪（不論 Status 是什麼）
   - 所有 Status 為 `IN_PROGRESS` 或 `BLOCKED` 的輪次，不論多舊
4. 其餘 Status 為 `DONE` 的舊輪次：依原本完整的 `## Round <N> — <時間戳>` 標題與內容，
   依原始順序 append 到 `.devlog/devlog.archive.md` 尾端（archive 檔案不存在就建立；已存在則接續寫在後面，不要覆寫或重排既有內容）。
5. 從 `.devlog/devlog.md` 移除步驟 4 搬走的區塊，其餘保持原樣（不要順便改寫使用者或先前 Claude 寫的內容）。
6. 完成後回報一句摘要：搬移了幾輪到 archive、devlog.md 目前剩幾輪、archive 檔案目前累積幾輪。

不要在使用者沒有要求的情況下自動觸發這個流程；這是使用者主動執行 `/devlog-tracker:compact` 時才做的事。
