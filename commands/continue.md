---
description: 讀取 .devlog/devlog.md，依最後一輪 Handoff 的下一步接著做。/clear 之後不會自動接續，要下這個指令才會讀檔。
---

請執行 devlog continue（接續上一題）。這是使用者主動執行 `/devlog-tracker:continue`，或明確說「continue」「接續」「繼續上一題」時才做的事。`/clear` 之後的一般新請求不要先讀檔接舊工作。

1. 讀取 `.devlog/devlog.md`。若檔案不存在，告知「目前沒有 devlog 可接續」，不要建立 `.devlog/` 或任何新檔，結束。
2. 若 `.devlog/.span-open` 存在：先告訴使用者有一個還沒關的 span（Round 編號與 `opened_at`，若讀得到），問要繼續這個自動化任務還是先關掉它。沒有明確要關就當成要繼續，不要自己刪 `.span-open`。
3. 讀最近的 Round（不夠再往前讀；有 `## Checkpoint` 就一併看最後一個）。不要讀 `devlog.archive.md` 或 `devlog.<name>.md`，除非 Handoff 下一步明確指向它們。
4. 依**最後一個歷史 Round**（不是這一輪 continue 自己的 skeleton）的 Status 行動：
   - `IN_PROGRESS` 或 `INTERRUPTED`：立刻依 Handoff「下一步」開始做。不要先問「上次做到哪」。沒有「下一步」就依「現況」推下一步並做。
   - `BLOCKED`：說明缺什麼外部輸入，停下來等，不要發明那個輸入。
   - `DONE`：告訴使用者上一題已經結束，等新需求。不要自己找下一件工作。
5. 這一輪若強制記錄開著，hook 已寫好 skeleton。編輯**這一個** Round 的 Summary / Handoff / Status，不要再新增一個 `## Round`。不要改歷史 Round 的本文。

`/devlog-tracker:start` 不是 continue：start 只開強制記錄並對進度；要接著做才用本指令。
