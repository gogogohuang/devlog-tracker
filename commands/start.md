---
description: 啟動這個專案的 devlog 強制記錄機制。之後每一輪結束前都會被 Stop hook 檢查，沒寫 devlog 就不能結束。
---

請執行以下步驟：

1. 確認 `.devlog/` 資料夾存在，不存在就建立。
2. 建立（若已存在就略過）`.devlog/.enabled` 這個檔案，內容隨意（例如寫入啟動時間），
   這個檔案存在與否就是「這個專案要不要強制記錄」的開關。
3. 讀取 `.devlog/devlog.md`（若存在）：
   - 有內容：摘要目前進度，跟使用者確認「上次做到哪、狀態是什麼」
   - 不存在：告知使用者這是全新開始，準備寫下 Round 1
4. 告訴使用者：從現在開始，每一輪結束前都會被要求先把這輪寫進 `.devlog/devlog.md`
   （User Input / Response / Status），可以用 `/devlog-tracker:pause` 隨時關掉這個強制機制。

不要因為 `.devlog/.enabled` 已經存在就跳過步驟 3 的進度摘要——每次執行 `/devlog-tracker:start`
都應該重新確認一次目前進度，這通常代表使用者是在新 session 或 `/clear` 之後手動觸發的。
