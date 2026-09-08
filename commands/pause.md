---
description: 暫停這個專案的 devlog 強制記錄機制。不會刪除任何歷史紀錄，只是之後 Stop hook 不再強制檢查。
---

請執行：

1. 如果 `.devlog/.enabled` 存在就刪除它（不要動 `.devlog/devlog.md` 或 `.devlog/devlog.archive.md`，
   歷史紀錄完整保留）。
2. 告知使用者強制記錄已暫停，之後可以用 `/devlog-tracker:start` 隨時重新啟動，之前寫過的內容都還在。

如果 `.devlog/.enabled` 原本就不存在，告知使用者這個專案本來就沒有啟動強制記錄，不用做任何事。
