---
description: 讀取 .devlog/devlog.md，核對最後一輪 Handoff 的工作區後再依下一步接著做。/clear 之後不會自動接續，要下這個指令才會讀檔。
---

請執行 devlog continue（接續上一題）。這是使用者主動執行 `/devlog-tracker:continue`，或明確說「continue」「接續」「繼續上一題」時才做的事。`/clear` 之後的一般新請求不要先讀檔接舊工作。

1. 讀取 `.devlog/devlog.md`。若檔案不存在，告知「目前沒有 devlog 可接續」，不要建立 `.devlog/` 或任何新檔，結束。
2. 若 `.devlog/.span-open` 存在：先告訴使用者有一個還沒關的 span（Round 編號與 `opened_at`，若讀得到），問要繼續這個自動化任務還是先關掉它。沒有明確要關就當成要繼續，不要自己刪 `.span-open`。
3. 讀最近的 Round（不夠再往前讀；有 `## Checkpoint` 就一併看最後一個）。不要讀 `devlog.archive.md` 或 `devlog.<name>.md`，除非 Handoff 下一步明確指向它們。
4. 依**最後一個歷史 Round**（不是這一輪 continue 自己的 skeleton）的 Status 行動。`DONE`：告訴使用者上一題已經結束，等新需求。不要核對、不要自己找下一件工作。
5. `IN_PROGRESS`、`INTERRUPTED`、`BLOCKED`：先核對，再行動。不要先問「上次做到哪」。不要改歷史 Round。
   1. 跑與寫「工作區」相同的指令：`git status --short`、`git rev-parse --abbrev-ref HEAD`、`git rev-parse --short HEAD`。不是 git repo 就當實際狀態為 `非 git 工作區`。不要重跑測試套件，除非「下一步」本身就是跑測試。
   2. 對照該歷史 Round 的 `#### 工作區`（分支、短 HEAD、未提交清單或「工作樹乾淨」）。沒有這一節（舊 Round、`INTERRUPTED` stub）就沒有可對的快照：以剛才跑出來的實際狀態為準。
   3. 相符：依 Status 做下一步——`IN_PROGRESS`／`INTERRUPTED` 做 Handoff「下一步」（沒有就依「現況」與實際工作區推出並做）；`BLOCKED` 仍缺外部輸入就說明缺什麼並停住，不要發明那個輸入。
   4. 不相符，或沒有快照：在**這一輪**先追加一段 `### 段落`，寫宣稱 vs 實際（分支／HEAD／髒檔）。然後依實際狀態行動：該做的下一步以工作區現況為準；`BLOCKED` 的缺件若已經出現就做，仍缺就停。
6. 這一輪若強制記錄開著，hook 已寫好 skeleton。編輯**這一個** Round 的 Summary / Handoff / Status，不要再新增一個 `## Round`。收尾時若 Status 是 `IN_PROGRESS`／`BLOCKED`，照契約寫本輪的 `#### 工作區`。

`/devlog-tracker:start` 不是 continue：start 只開強制記錄並對進度；要接著做才用本指令。
