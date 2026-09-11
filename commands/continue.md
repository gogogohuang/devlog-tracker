---
description: 讀取 .devlog/devlog.md，核對最後一輪 Handoff 的工作區後再依下一步接著做。/clear 之後不會自動接續，要下這個指令才會讀檔。
---

請執行 devlog continue（接續上一題）。這是使用者主動執行 `/devlog-tracker:continue`，或明確說「continue」「接續」「繼續上一題」時才做的事。`/clear` 之後的一般新請求不要先讀檔接舊工作。

1. 讀取 `.devlog/devlog.md`。若檔案不存在，告知「目前沒有 devlog 可接續」，不要建立 `.devlog/` 或任何新檔，結束。記下這個檔案所在目錄的絕對路徑，作為本輪接下來都要用的專案根目錄——後面步驟（尤其是步驟 5.1）一律沿用這個值，不要再用 shell 的 `pwd` 重新推。Bash 工具的工作目錄會在同一段對話裡的呼叫之間持續累積，中途若因為別的原因 `cd` 過，`pwd` 就不再代表這個專案根目錄。
2. 若 `.devlog/.span-open` 存在：先告訴使用者有一個還沒關的 span（Round 編號與 `opened_at`，若讀得到），問要繼續這個自動化任務還是先關掉它。沒有明確要關就當成要繼續，不要自己刪 `.span-open`。
3. 讀最近的 Round（不夠再往前讀；有 `## Checkpoint` 就一併看最後一個）。不要讀 `devlog.archive.md` 或 `devlog.<name>.md`，除非 Handoff 下一步明確指向它們。
4. 依**最後一個歷史 Round**（不是這一輪 continue 自己的 skeleton）的 Status 行動。`DONE`：告訴使用者上一題已經結束，等新需求。不要核對、不要自己找下一件工作。
5. `IN_PROGRESS`、`INTERRUPTED`、`BLOCKED`：先核對，再行動。不要先問「上次做到哪」。不要改歷史 Round。
   1. 跑與寫「工作區」相同的生產者，不要自己跑 git、不要手編成 SKILL 的七種格式。先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：
      ```bash
      PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
      CLAUDE_PROJECT_DIR="<步驟 1 記下的專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/hooks/scripts/workspace-snapshot.sh"
      ```
      把 `CLAUDE_PROJECT_DIR` 換成實際的絕對路徑字串再執行，不要真的呼叫 `pwd`。stdout 就是實際快照（1 行或 2 行）。腳本檔找不到時才退回 `skills/devlog-tracker/SKILL.md` `#### 工作區` 的七種格式手編。不要重跑測試套件，除非「下一步」本身就是跑測試。
   2. 把編成的實際快照對照該歷史 Round 的 `#### 工作區` 正文。
      - 沒有這一節（舊 Round、`INTERRUPTED` stub）：沒有宣稱可對，不算「不符」——不用寫 `### 段落`，直接以剛才編成的實際快照為準。
      - 有這一節但跟編成的實際快照不符：在**這一輪**先追加一段 `### 段落`，寫宣稱 vs 實際（用剛才腳本的 stdout 當實際快照）。
      - 有這一節且相符：不用寫 `### 段落`。
   3. 然後依**實際工作樹**行動（不要照 Handoff「工作區」或「現況」的字面當事實）：
      - `IN_PROGRESS`／`INTERRUPTED`：做 Handoff「下一步」（沒有就依「現況」與實際工作樹推出並做）。
      - `BLOCKED`：看缺的外部輸入本身在不在——已經出現就做下一步；仍缺就說明缺什麼並停。git 相不相符不能證明缺件已到，不要發明輸入。
6. 這一輪若強制記錄開著，hook 已寫好 skeleton。編輯**這一個** Round 的 Summary / Handoff / Status，不要再新增一個 `## Round`。收尾時若 Status 是 `IN_PROGRESS`／`BLOCKED`，照契約寫本輪的 `#### 工作區`。

`/devlog-tracker:start` 不是 continue：start 只開強制記錄並對進度；要接著做才用本指令。
