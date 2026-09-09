---
description: 暫停這個專案的 devlog 強制記錄機制。不會刪除任何歷史紀錄，只是之後 Stop 與 PreToolUse hook 都因 `.enabled` 移除而停止檢查。
---

請執行：

1. 如果 `.devlog/.enabled` 存在就刪除它（不要動 `.devlog/devlog.md` 或 `.devlog/devlog.archive.md`，
   歷史紀錄完整保留）。
2. 如果 `.devlog/.span-open` 存在也一併刪除它——強制記錄都暫停了，殘留的 span 標記
   沒有意義，留著只會讓之後重新 `/devlog-tracker:start` 時繼承一個指向舊 Round 編號
   的過期 span。
3. 如果 `.devlog/.round-open` 或 `.devlog/.interrupted` 存在也刪掉——暫停不是崩潰，
   不要讓下次 start 把當下的 skeleton 標成 INTERRUPTED。不要改 `devlog.md` 裡已寫的 Round。
4. 不要刪 `.devlog/.segment-state` 或 `.devlog/.checkpoint-state`——暫停只關強制，
   門檻數字要留到下次 `/devlog-tracker:start`。
5. 告知使用者強制記錄已暫停，之後可以用 `/devlog-tracker:start` 隨時重新啟動，之前寫過的內容都還在。

如果 `.devlog/.enabled` 原本就不存在，告知使用者這個專案本來就沒有啟動強制記錄，不用做任何事。
