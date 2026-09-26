---
name: devlog-tracker
description: 在專案的 .devlog/devlog.md 維護逐輪對話紀錄。使用者下 /devlog-tracker:start 後 Stop hook 強制每輪寫入；SessionStart 在 startup / resume / compact / fork 注入進度，/clear 不注入；要接續用 /devlog-tracker:continue。當使用者提到「devlog-tracker」「.devlog/devlog.md」「/devlog-tracker:continue」或明確要寫／接續這份紀錄時使用。
---

# Devlog Tracker

## Contract

每輪收尾／接手前先對齊這七項；細節與例外見下方章節與
`references/contract.md`（審核用展開，不取代本節）。

| 維度 | 契約（短） |
|---|---|
| **Requirements** | 強制記錄需 `.devlog/.enabled`（Claude plugin 用 `/devlog-tracker:start`，Codex 用 `$devlog-start`）。`/clear` 後不自動接續；要開工用對應的 continue 指令（或明確說接續）。Cursor／npx 安裝的 Codex 對照 `.devlog-tracker/commands/*.md`；Codex plugin 對照 plugin 根目錄的 `commands/*.md`。 |
| **Output** | 編輯開著的 Round（`.round-current.md`）：必有 `### Summary`／`### Reply`／`### Handoff`／`### Status`；Handoff／Session Handoff 用 XML 標籤，標籤順序固定。格式見「每一輪的紀錄格式」。 |
| **Invariants** | L1 寫回義務；聊天不旁白記錄動作；不改 User Input（除非 hook `（無 prompt）`）；不為同一則訊息再 append `## Round`；設計真相在 `docs/design/*.md`，不是 lessons。 |
| **Validation** | Soft：收尾前自檢欄位與工作區。Hard：Stop／PreToolUse／workspace／files snapshot（見「每一輪的紀錄格式」末段與 hook 腳本）。fail-open／loop guard 見下方開關一節。 |
| **Transformation** | 單次動作走對應 `commands/*.md`（start／continue／compact／keep／…）；本檔管協定與跨指令不變式，不重抄步驟。 |
| **Knowledge** | 檔案位置、分支主檔、mode 邊界見下方與 `references/*`；更深設計見 `docs/design/*`。 |
| **Observation** | 收尾／接手前看：開著的 Round、live git（`workspace-snapshot.sh`）、Handoff「完成條件」／「下一步」、是否該寫 `### 段落`（瑣碎度表、Segment Watch）。 |

## 核心原則

devlog.md 是**跨 session 交接連續性**（決策軌跡、目前卡點、下一步、完成條件）的 single source of truth，
也是 L1「人觸發 continue／開 session 後 agent 可接手」的主入口；接手輪必須把狀態**寫回**本檔。
不是整個專案的單一真相來源：程式碼／檔案狀態的真相仍是 git（工作區（`<workspace>`）是收尾當下的已核對快取：
`IN_PROGRESS`／`BLOCKED` 時 Stop hook 一律對過 live git，`DONE` 若「檔案」有內容也對過；接手時樹可能已變，`continue`／`resume`
仍以實際工作樹為準，見 `docs/design/continue.md`）；完整逐字過程的真相是對話 transcript（`/clear` 後不存在）；設計
決策的真相是 `docs/design/*.md`。使用者在裡面許願、Claude 也在裡面回報進度與結果——取代「終端機
一 clear 就沒了」的對話記錄，讓工作可以隨時中斷、隨時接續。L2（無人喚醒）與 L3（跨機共享 `.devlog/`）不在範圍。

## 寫進 devlog 不等於講給使用者聽

`### Summary`／`### Reply`／`### Handoff`／`### 段落`／`## Checkpoint` 這些內容是寫給「下一個
讀 devlog.md 的人」看的，不是講給正在對話的使用者聽的——這是兩件不同的事，收尾時
用 Edit／Write 工具**安靜地**寫進 `.devlog/.round-current.md`（這一輪還開著時的
實際編輯對象，收尾成功或被判定中斷後才會由 hook 自動併回 `.devlog/devlog.md`；
工具呼叫本身不會顯示給使用者），寫完之後**不要**在聊天回覆裡再提這件事。

具體來說，這輪收尾的聊天回覆裡：

- **不要**出現「devlog」「Round」「Summary」「Handoff」「Reply」「Status」「這一輪」這些字，
  也不要說「已寫入」「已補上」「已記錄」「收尾完成」之類的動作旁白——使用者看不到
  你剛剛用工具做了什麼，講這些等於自己報告一件使用者沒問過的事，是雜訊。
- **不要**把剛寫進 Handoff／Summary／Reply 的內容（決策、下一步、現況、對使用者說過的話）換句話再講一次。
  如果使用者原本就在等這個結論，直接把結論講給他聽即可，不用先鋪一句「我把這輪記
  錄下來了」再講結論。
- 唯一的例外是使用者自己開口問跟 devlog 有關的事（例如問「這輪有記錄嗎」「幫我看
  一下 devlog」），這時才正常回答。

**反例**（不要這樣回）：「devlog 已補上這輪的 Summary/Handoff/Status（標記
IN_PROGRESS，因為背景任務還在跑）。等它跑完我會回報結果並更新這一輪。」

**正例**（改成這樣）：「background 任務還在跑（daily_tune.py 那段約 11.5
分鐘），跑完我會回報結果。」——結論相同，但完全不提 devlog／Round／Handoff 這些
內部記錄動作。

**最容易漏掉的一種情況：結尾的「這輪改了什麼」總結。** 這輪如果除了
`.devlog/.round-current.md`（收尾後才會併入 `devlog.md`）還真的改了別的檔案
（例如 README.md、程式碼），結尾照常給一兩句話總結改了什麼、下一步是什麼——
但這個異動本身**不算在「改了什麼」裡面，永遠不要提**，因為那是記錄動作本身、
不是產出。舉例：這輪同時修了 `README.md` 又寫了 `.devlog/.round-current.md`，
結尾只講「README.md 已更新成...」，不要接著再講「devlog 也已更新／已補上這輪的
Summary/Handoff」——後面這句要整句刪掉，不是縮短。

## 檔案位置

- 主檔：`.devlog/devlog.md`——在 `main`／`master` 分支上工作時使用
- 分支主檔：`.devlog/devlog.<branch>.md`——在同一個 worktree 裡切換到其他分支時，主檔會依目前 checkout 的分支自動分開（斜線轉成 `-`）；detached HEAD 退回用 worktree 目錄名。另開一個 `git worktree`（不同目錄）本來就有自己獨立的 `.devlog/`，不受這個機制影響。第一次在某分支偵測到還沒有專屬檔案時，只會把 `devlog.md` 裡還沒完成的尾巴（最後一個 `DONE` 之後的 Round，連同 `handoff.md`）剪到該分支的檔案；`main` 自己的歷史、專案摘要、Checkpoint、Kept／Lessons 索引都留在 `devlog.md`。最後一輪已經是 `DONE`，或切到的是不含目前 `main` 最新 commit 的舊分支時，什麼都不搬，新分支從空檔開始。分支檔第一行是 origin 標記 `<!-- devlog-origin: branch=<原始分支名> -->`（detached HEAD 是 `detached=<目錄名>`），由 hook 在建立分支檔時寫入；不要刪改這一行。細節見 `docs/design/branch-scoped-devlog.md`。
- 歸檔：`.devlog/devlog.archive.md`
- 具名保存：`.devlog/devlog.<name>.md`（`/devlog-tracker:keep`／`keep-all` 搬走的主題檔，第一行是 `# Kept log`；SessionStart 不讀這些檔）
- keep-all 備份：`.devlog/.keep-all-backup/<時間戳>/`（`/devlog-tracker:keep-all` 動手前的原始檔複本）
- 當輪暫存：`.devlog/.round-current.md`（目前開著的那一輪，Claude 該讀寫的是這個檔，不是 `devlog.md`；
  收尾或中斷時由 hook 自動合併回 `devlog.md` 並清空，設計見 `docs/design/round-current-split.md`）
- Session Handoff 快照：`.devlog/handoff.md`（`main`／`master`）；其他分支 `.devlog/handoff.<branch>.md`。
  由 Stop 在 `IN_PROGRESS`／`BLOCKED` 收尾時覆寫、`DONE` 時刪除；Claude 只寫 Round 內的
  `### Session Handoff`，不要直接編這個檔。設計見 `docs/design/session-handoff-file.md`。
- Cursor／Codex 上沒有 `/devlog-tracker:*` slash 選單。若專案是用 `npx devlog-tracker init` 裝的，指令對照就是 `.devlog-tracker/commands/*.md`：先 `source .devlog-tracker/env.sh`，再照使用者意圖對應的那份 `.md` 檔案的步驟做。Codex plugin 安裝時，指令對照在 plugin 根目錄的 `commands/*.md`，也可直接用 `$devlog-start` 等 skill。手動裝的專案見 README 安裝章節。

第一次使用時，若 `.devlog/` 不存在就建立它。

本文件與各 `commands/*.md`、`references/*.md` 提到「devlog.md」或「主檔」時，
若專案目前不在 `main`／`master` 分支，指的實際上是該分支對應的
`devlog.<branch>.md`（規則見上）——這些文件不會逐一改寫成分支中立的說法，
以此為準即可。

## 用 `/devlog-tracker:start` 明確開啟強制記錄（不用猜這輪有沒有呼叫到 skill）

Claude Code 目前沒有正式、穩定的方式讓 hook 知道「這一輪有沒有呼叫到某個 skill」，
所以這裡不猜也不解析 transcript，改用一個明確的開關檔案 `.devlog/.enabled`：

- 使用者下 `/devlog-tracker:start`：建立這個開關檔（見 `commands/start.md`），代表「這個專案從現在起
  要強制記錄」，同時讀一次現有 devlog 摘要目前進度（對進度，不自動開工）
- 使用者下 `/devlog-tracker:continue`：讀現有 devlog，核對最後一輪 Handoff「工作區」後再依下一步接著做（見
  `commands/continue.md`）。`/clear` 之後要接續，用這個，不要用 start
- 使用者下 `/devlog-tracker:pause`：刪掉開關檔，暫停強制記錄，但完全不動歷史紀錄
- 沒下過 `/devlog-tracker:start` 的專案：這個 plugin 裝著也不會有任何動作，不會留下 `.devlog/` 檔案

開關啟動之後，才會進入下面這套強制流程：

1. 使用者送出新訊息時，`UserPromptSubmit` hook（`core/scripts/round-start.sh`）
   若開關開著，就在 `.devlog/.round-current.md` 寫入這一輪的 skeleton（`### User Input`
   + `Status: IN_PROGRESS`），並寫 `.devlog/.round-open`。
2. Claude 編輯**同一個** Round：不要再 append 一個新的 `## Round`。不要改 User Input
   （除非裡面是 hook 的 `（無 prompt）` 占位）。補上 `### Summary` / `### Reply` / `### Handoff`，
   把 Status 改成 `DONE` / `IN_PROGRESS` / `BLOCKED`。這一輪還開著的時候，編輯的對象
   是 `.devlog/.round-current.md`，不是 `devlog.md`——這一輪還沒併回去之前，
   `devlog.md` 完全看不到它。
3. `Stop` hook（`core/scripts/enforce-devlog.sh`）若雜湊沒變、或最後一個 Round
   缺少 `### Summary` / `### Reply` / `### Handoff`，就用 exit code 2 擋下來。通過則刪掉
   `.round-open`，並把 `.round-current.md` 的內容併回 `devlog.md` 尾端、清空
   `.round-current.md`（設計見 `docs/design/round-current-split.md`）。

好處：就算工作做到一半被中斷（下一輪還沒開始就被使用者關掉、或換 session），
只要**上一輪有正常結束過**，devlog.md 就一定留有當時的 Status（多半是 `IN_PROGRESS`
或 `BLOCKED`）可以接續——這跟「plan 是否完成」完全無關，純粹綁在「這一輪有沒有結束」
這個事件上。

需要誠實說明的邊界：User Input 在送出當下就已經在 `.devlog/.round-current.md`
（收尾成功或被判定中斷後才會併回 `devlog.md`）。正常結束時 Stop 仍保證有 Summary / Reply / Handoff。
意外中斷會把同一塊標成 `INTERRUPTED`（process 被殺、或 mid-turn 取消時，Status 通常要等
**下一則訊息**或**下次 SessionStart（startup / resume / clear / fork）**才補上）。
`PostToolUseFailure` 的 `is_interrupt` 若有觸發，只是 best-effort 的額外路徑，不能當成 Esc
會立刻蓋章。中間沒寫成 `### 段落` 的過程仍會丟——Segment Watch 只在還有下一個工具呼叫時催促。

hook 本身出錯時一律放行（fail-open），同一輪被 Stop 擋過一次後重跑也會放行（loop guard）；
設計說明見 `core/scripts/enforce-devlog.sh` 開頭註解。

## 自動接續與 `/clear`

這個 plugin 內建一個 SessionStart hook（`claude/hooks.json` + `core/scripts/session-start-devlog.sh`），
matcher 設為 `startup|resume|clear|compact|fork`。**開新 session、resume、`/compact`、`/fork`**
時會自動讀檔注入；**`/clear` 不會注入**——對話清空就是空的。

自動注入時：

1. 若目前分支的 `.devlog/handoff.md`（或 `handoff.<branch>.md`）非空，先注入這份 Session Handoff 快照
2. 再讀取 `.devlog/devlog.md`，注入最後一個 `## Checkpoint`（若有）、最後一個 `## Kept 索引`（若有；不是具名檔內容）、最後一個 `## Lessons 索引`（若有），加上最近 2 輪的 Summary / Handoff / Status（沒有 Summary 的 skeleton 才帶 User Input）

這段摘要會出現在 session 開頭的 context 裡。

`/clear` 時 hook 仍可能把殘留的開著 Round 標成 `INTERRUPTED`，但 stdout 什麼都不印。
之後只有使用者下 `/devlog-tracker:continue`，或明確說「continue」「接續」「繼續上一題」時，
才讀 `.devlog/devlog.md`，核對 Handoff「工作區」後再依下一步接著做（見 `commands/continue.md`）。
一般新請求當成空白對話，不要先讀檔接舊工作。`/devlog-tracker:start` 只對進度，不開工。

找不到 `.devlog/devlog.md` 時 hook 直接 exit 0，不輸出任何東西，不會干擾沒有用 devlog 的專案。

如果 hook 在 startup / resume / fork 沒有生效（例如使用者不是用 Claude Code、或 hook 因為某些
環境問題沒跑），Claude 仍應主動：使用者在已有 devlog.md 的專案裡提出一般開發需求時，先讀一次
`.devlog/devlog.md` 最後幾輪。最後一輪 `DONE`：只對進度，不核對、不開工。否則依
`commands/continue.md` 步驟 5 核對後再接手。
這個 fallback **不適用於 `/clear` 之後**——clear 之後沒有說 continue，就不要讀檔。

## 接續：`/devlog-tracker:continue`

`/clear` 之後要接著做上一題，下 `/devlog-tracker:continue`（或明確說「continue」
「接續」「繼續上一題」）。讀 `devlog.md`，**先核對**最後一輪 Handoff 的工作區（`<workspace>`；舊格式 `#### 工作區`）
（跑步驟 5.1，編成同一格式再對），再依「下一步」開工，並對照「完成條件」。有快照但不符才先寫 `### 段落`；
沒有快照（舊 Round、`INTERRUPTED` stub）直接以實際狀態為準，不用寫。步驟見 `commands/continue.md`。
`DONE` 就說明上一題已結束、等新需求，不核對。`BLOCKED`：缺的外部輸入仍缺就停，已經出現就做；
不要用 git 相不相符當作缺件已到。SessionStart 注入的摘錄若讓你要動手做「下一步」，同樣先核對。
同一條對話的下一則訊息也一樣：UserPromptSubmit 若發現上一輪工作區（`<workspace>`）跟 live git 不符，會注入說明並在 PreToolUse 擋住其他工具，直到這一輪寫了含實際快照的 `### 段落`。Span 安靜 tick 與 task-notification 不擋。`DONE` 一律不擋（跟 Stop hook 不同：Stop 在 `DONE` 有「檔案」時會機器核對，但這裡管的是「上一輪的宣稱還能不能拿來接續下一步」——`DONE` 沒有下一步可接，即使當初有檔案也不用重查）。沒呼叫任何工具的純文字回覆不會碰到 PreToolUse，仍應先核對再依實際工作樹行動。擋著的時候，唯讀的 `git status`／`diff`／`log`／`show`／`rev-parse`（不含任何 shell 串接符號）仍可執行，方便自行核對「宣稱 vs 實際」再動手寫段落。
不要自動觸發。`/devlog-tracker:start` 只對進度，不開工、不核對。

### L1 寫回義務

接手（continue、SessionStart 注入後依下一步行動、或同 session 接著做）不是「讀檔 → 改程式 → 結束」。
**同一輪必須把狀態寫回** `.devlog/devlog.md`（本輪 Round 的 Summary／Reply／Handoff／Status），讓下一任只靠檔案就能再接。讀而不寫 = 交接斷鏈 = L1 失敗。有 `.enabled` 時 Stop 會擋；沒有 Stop／未 start／Cursor 未裝 hook 時仍要自行寫回。子 agent 若只改 code，主對話負責收尾寫回（或 brief 要求子任務寫回）。聊天不要旁白「已寫入 devlog」。

## 每一輪的紀錄格式

hook 已在送出時寫好 User Input；Claude **編輯最後一個 Round**，不要為同一則使用者訊息再新增一個 `## Round`：

```markdown
## Round <N> — <ISO 8601 時間戳，含時區>

### User Input
<使用者這輪的輸入：預設保留送出原文；見下方 User Input 原則>

### Summary
<2–4 句，給人掃：這輪結論、有沒有卡住。不要寫檔案路徑、commit hash、skill 名稱、逐步指令>

### Reply
<這輪實際對使用者說的話／答應的邊界／未決提問，短述即可。給下一輪知道承諾，不是 Handoff>

### Handoff
<handoff>
<decisions>
影響後續方向的選擇與理由（沒做選擇就整個標籤省略）
</decisions>
<files>
尚未 commit：
修改：path/to/file
</files>
<workspace>
main @ a1b2c3d，工作樹乾淨
</workspace>
<state>
任務做到哪、卡在哪
</state>
<done-when>
可觀察的做完判準（IN_PROGRESS／BLOCKED 必寫）
</done-when>
<next>
下一輪第一件具體要做的事（IN_PROGRESS／BLOCKED 必寫）
</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- 仍影響後續方向的選擇；沒有就寫 - （無）
</decisions>
<open-questions>
- 下一 session 最該先看的卡點；沒有就寫 - （無）
</open-questions>
<failed-attempts>
- 試過但放棄的做法；沒有就寫 - （無）
</failed-attempts>
</session-handoff>

### Status
DONE | IN_PROGRESS | BLOCKED | INTERRUPTED
```

**Handoff／Session Handoff 用 XML 標籤（只有這兩節）：** 讀者是下一輪的 agent 與 Stop hook，不是人。規則：

- 標籤自己一行（`<next>`、`</next>` 各佔一行），內容寫在中間，照常用 Markdown；不要寫成 `<next>做 X</next>`。
- 標籤名固定、順序固定；沒發生的欄位整個標籤省略，不要留空標籤。
- 這不是真的 XML：不用跳脫 `<`、`&`，不要加屬性。
- 舊的 `#### 小節` 格式只會出現在歷史輪次，讀取時仍相容；這一輪寫舊格式會被 Stop 擋下，照訊息跑 `migrate-handoff.sh` 即可。

| 標籤 | 舊格式小節 | 所在區塊 |
|---|---|---|
| `<decisions>` | `#### 決策` | Handoff、Session Handoff |
| `<files>` | `#### 檔案` | Handoff |
| `<workspace>` | `#### 工作區` | Handoff |
| `<state>` | `#### 現況` | Handoff |
| `<done-when>` | `#### 完成條件` | Handoff |
| `<next>` | `#### 下一步` | Handoff |
| `<open-questions>` | `#### 待解問題` | Session Handoff |
| `<failed-attempts>` | `#### 失敗嘗試` | Session Handoff |

下文提到「決策」「檔案」「工作區」「現況」「完成條件」「下一步」時，指的就是對應標籤。

Round 編號：讀取檔案中最後一個 `## Round <N>`，本輪用 N+1；檔案不存在就從 Round 1 開始。

寫入原則：
- **User Input：送出原文優先。** hook 在 `UserPromptSubmit` 已寫入送出當下的 prompt（截斷／遮罩規則見
  `docs/design/recording-moments.md`）。Claude **不要改寫、不要潤飾、不要事後摘要取代原文**，除非
  裡面是 hook 的 `（無 prompt）` 占位。目標是讓人「只讀這份檔案、不用翻對話紀錄」就能接續；關鍵措辭
  （用詞、並列條件、例外）必須留在檔裡。超長內容由 hook 截斷並標明；不要在收尾時再手動縮成更短的改寫版。
- **三個讀者拆開：** `Summary` 只給人掃；`Reply` 只記對使用者說過／答應過的話；`Handoff` 只給下一輪
  Claude 接手。同一件事不要三邊複述。
- **`### Session Handoff`（跨 session 精簡快照）：** 與 Checkpoint 同款三個標籤（`decisions`／
  `open-questions`／`failed-attempts`），不是 `### Handoff` 六個標籤的複本。`IN_PROGRESS`／`BLOCKED`
  必寫（可 `- （無）`）；`DONE` 不要求，但 DONE 輪若寫了仍會被當 XML 驗證（是否存在採 fence-aware 判斷，標題須剛好是
  `### Session Handoff`）；`INTERRUPTED` stub 不寫。Stop 通過後會把整個 `<session-handoff>`
  區塊原樣寫進 `.devlog/handoff.md`（分支檔同規則）；`DONE` 會刪掉該檔——不要把長期軌跡只寫在
  handoff 檔裡。細節見 `docs/design/session-handoff-file.md`。
- Handoff 標籤順序固定（`decisions` → `files` → `workspace` → `state` → `done-when` → `next`），Stop hook
  會檢查已出現的標籤順序有沒有錯、有沒有重複（不檢查內容對不對）。沒發生的整個標籤省略，不要寫「無」。
  `現況` 幾乎每輪都該有。`工作區`、`完成條件` 與 `下一步` 在 `IN_PROGRESS`／`BLOCKED` 必寫；`DONE` 且沒有後續就整節省略——
  但 `DONE` 若 `檔案` 有內容（宣稱動過／commit 過檔案），`工作區` 一樣必寫且會被 Stop hook 機器核對，
  避免「已 commit 完成」卻其實沒 commit 這種宣稱跟實際不符沒人發現。
  `完成條件` 要寫到下一輪能對照判斷「可否 DONE」（例如「`bash core/scripts/tests/test-foo.sh` 全過」），
  不要只寫「功能完成」。`下一步` 要具體到下一輪打開就能做（路徑／反引號指令／skill 名），寫「繼續完成」不算完成；
  `IN_PROGRESS` 時 Stop 會做輕量可執行檢查（見下）。`BLOCKED` 的 `現況` 或 `下一步` 必須寫「缺什麼、出現長怎樣」。
- **`工作區` 是收尾當下的 git 快照，給下一輪核對用。** 寫之前跑 `git status --short`、`git rev-parse --abbrev-ref HEAD`、`git rev-parse --short HEAD`，照輸出寫。`abbrev-ref` 為 `HEAD` 時用 detached 格式；`rev-parse --short HEAD` 失敗但 `git symbolic-ref --short HEAD` 抓得到分支名（尚無 commit，例如剛 `git init`）用 unborn 格式；兩者都失敗才是非 git。髒檔是整棵樹的未提交，不必跟「檔案」那輪 delta 相同；`.devlog/` 底下的路徑不列（devlog 每輪都會改，只有它髒時照「工作樹乾淨」寫）。格式：
  - 乾淨：`main @ a1b2c3d，工作樹乾淨`（一行）
  - 有未提交：第一行 `feat/foo @ a1b2c3d`，第二行 `未提交：src/a.ts, hooks/foo.sh`
  - 非 git：一行 `非 git 工作區`
  - detached 乾淨：`HEAD detached @ a1b2c3d`（一行）
  - detached 有未提交：第一行 `HEAD detached @ a1b2c3d`，第二行 `未提交：src/a.ts, hooks/foo.sh`
  - unborn（尚無 commit）乾淨：`main @ (尚無 commit)，工作樹乾淨`（一行）
  - unborn（尚無 commit）有未提交：第一行 `main @ (尚無 commit)`，第二行 `未提交：src/a.ts, hooks/foo.sh`
  （七種格式的機器生產者只有 `core/scripts/workspace-snapshot.sh`。寫入照上面手寫；Stop 用同一 function 核對。改格式時改 SKILL 與該腳本，不要在 continue.md 再抄一份。）
  `INTERRUPTED` stub 不寫這一節。`IN_PROGRESS`／`BLOCKED` 收尾時，Stop hook 會自己算一次
  即時 git 快照，跟這一節逐字比對，不符就擋下來並印出正確內容（`core/scripts/workspace-snapshot.sh`，
  docs/design/devlog-as-ssot-assessment.md Phase 1）；`DONE` 若「檔案」有內容一樣核對——只有
  沒動檔的 `DONE` 與 `INTERRUPTED` 不受影響。
  接手跑 `workspace-snapshot.sh`（`PLUGIN_ROOT` 同其他指令），stdout 就是要對的快照，不要手編（continue／fallback 見 `commands/continue.md` 步驟 5；resume 只做 5.1–5.2，等確認才做下一步）。腳本找不到才退回上面七種格式手編。
- **`<files>` 是機器可核對的區塊格式（devlog ssot Phase 4）。** 零個以上 `commit <hash>：` 區塊
  （commit 短 hash，依時間序），每個後面接最多三行分類（`新增：`/`修改：`/`刪除：`，逗號分隔路徑，
  沒有就省略那行）；最多一個 `尚未 commit：` 區塊，格式相同。一輪可以先 commit 一部分、後面
  繼續改，兩種區塊可以並存。Stop hook 對 `commit` 區塊做逐字精確核對（含分類），對
  `尚未 commit` 區塊只核對「宣稱的路徑是否真的在目前髒檔清單裡」（不核對分類，也不要求
  涵蓋所有髒檔——跨輪殘留、還沒 commit 的舊檔案不算這輪漏列）。Rename 一律回報成
  刪除+新增，不是第四類。`.devlog/` 路徑不算進比對。看不懂的行（沒有照這個格式寫）會被擋下來，
  不是 fail-open——這是 Claude 該產生的格式，不是可有可無的宣告。細節見
  `docs/design/files-verify.md`（`core/scripts/files-snapshot.sh`）。
- Handoff 只寫已發生的事；未來式只允許出現在「下一步」與「完成條件」。
- `Status` 只寫 `DONE`、`IN_PROGRESS`、`BLOCKED`、`INTERRUPTED` 其中一個，不要在下面再附「接下來要做什麼」
  （那句搬進 Handoff 的「下一步」）。`IN_PROGRESS` = 還能做；`BLOCKED` = 缺外部輸入；
  `DONE` = 這輪請求已結束（應已滿足「完成條件」或本輪請求本身已結束）。**例外只有 hook 自動蓋 `INTERRUPTED` 時**：`close-open-round.sh`
  會在下面多印一行 `[reason: ...]`（例如 `[reason: dangling:next_prompt]`），這是 hook 自己的
  除錯代號、用方括號標記成內部 metadata，特意不用 HTML 註解（會被 Markdown 渲染器整段隱藏，
  之後要 debug 反而看不到），不算違反「只寫一個值」——看到這行不用當成錯誤，Claude 也不用去動它。
- 若 Lessons Mode 開著（`.lessons-enabled` 存在）：寫這個 Status 前，想一下這輪算不算「從
  `BLOCKED` 解開」或「明顯繞了一圈才找到對的做法」——符合任一種就考慮用 `lessons-append.sh`
  記一筆，非強制。前者下一輪開始時 hook 也會機械印一句提示（見下面「Lessons Mode」一節），
  後者完全仰賴這裡的自我檢查，hook 判斷不到。
- `INTERRUPTED` 只由 hook 在意外中斷時寫上（非 usage 的 API 錯誤、SessionEnd、
  下次 SessionStart（startup / resume / clear / fork）或下一則訊息發現 `.round-open` 還在）。
  mid-turn 取消（例如 Esc）通常也是走這條延後路徑；`PostToolUseFailure` 的 `is_interrupt`
  若有觸發只是 best-effort，不能當成一定會立刻蓋章。Claude 正常收尾時不要自己選這個值。
  usage 用光（`rate_limit` / `billing_error` / `account_on_hold`）不標中斷。
- 每輪一個區塊，不要把多輪內容合併寫成一個 Round。
- 不要另外開欄位列「這輪用了哪些 skill」——那是稽核用途，跟接續開發沒有直接關係。只有
  當接續動作**必須**重新載入某個特定 skill 才能正確接手時，才把 skill 名稱寫進 Handoff
  「下一步」裡。

最後一輪的 Handoff／Session Handoff 必須是 XML 標籤格式（舊 `####` 格式會被擋，訊息附 migrate 指令與模板）。
Stop hook 會檢查最後一個 Round 是否同時有 `### Summary`、`### Reply` 與 `### Handoff`、三者底下有內容、`### Status` 是四個合法值之一，已出現的 Handoff 標籤順序與不重複（`decisions` → `files` → `workspace` → `state` → `done-when` → `next`），以及 `IN_PROGRESS`／`BLOCKED` 時 Handoff 有「完成條件」（`<done-when>`）與「下一步」（`<next>`）且「下一步」不是純黑名單空話（例如整節只寫「繼續完成」，見 `docs/design/next-step-blacklist.md`；這是字串比對，不是語意評分）；`IN_PROGRESS` 的「下一步」另做輕量可執行檢查（須含路徑、反引號指令、或檔名／skill 跡象）；`BLOCKED` 時「現況」（`<state>`）或「下一步」須含缺件句式（缺／等待／等使用者等）；工作區（`<workspace>`）跟 hook 算出的 git 快照相符——`IN_PROGRESS`／`BLOCKED` 一律核對，`DONE` 則只在「檔案」（`<files>`）有內容時才核對（瑣碎、沒動檔的 DONE 輪不受影響）；`<files>` 非空時，hook 也會核對它是否符合實際 git 變更（commit 區塊精確核對，未 commit 區塊單向核對，見上方「檔案 machine-verify」）；`IN_PROGRESS`／`BLOCKED` 還必須有完整的 `### Session Handoff`（`decisions`／`open-questions`／`failed-attempts`），通過後把 `<session-handoff>` 區塊原樣覆寫到分支對應的 `handoff.md`，`DONE` 則刪除該檔。
新開的 Round 三個標題（Summary／Reply／Handoff）都要有，瑣碎輪也不例外。

### devlog-tracker 自己的管理指令不記錄

這一輪如果是使用者直接呼叫 devlog-tracker 自己的純管理指令——`/devlog-tracker:checkpoint`、
`clean`、`compact`、`keep`、`keep-all`、`lessons`、`lessons-drift`、`lessons-off`、`lessons-on`、
`overview`、`pause`、`report`、`search`、`segment-watch`、`span`、`start`、`status`、`timeline`——`round-start.sh`
會整輪直接放行，不開 Round、不動任何計數器，等於這個 tick 沒發生過；不用、也不會被
Stop hook 要求補寫 Summary／Reply／Handoff。這些指令本身就是在操作 devlog 系統，不是開發
工作，記錄下來對接續開發沒有幫助。

`/devlog-tracker:continue` 與 `/devlog-tracker:resume` **不在此列**：這兩個指令執行完會接著
做實際開發工作（可能在同一輪裡做很多事），仍照正常規則強制記錄。

### 怎麼判斷這輪該寫多細（瑣碎程度）

「每輪都要記錄」管的是**要不要留下這一輪的痕跡**，瑣碎程度管的是**該寫多細**，這是兩件
不同的事——瑣碎不代表可以跳過不記，只代表這輪該寫得短。

判斷測試：**如果把這一輪從 devlog 刪掉，之後光讀檔案接續工作，會不會漏掉重要資訊？**
會漏掉就不瑣碎，要完整寫；不會漏掉（純確認、閒聊、使用者只回「好」「謝謝」、沒有產生任何
實質變化或懸而未決的事）就是瑣碎，但**還是要有這個 Round 區塊**，只是 Summary 一句話、
Reply 一句（對使用者說過的話）、Handoff 只留 `<state>` 一句（沒有 `<workspace>`），Status 多半 `DONE`。三個標題仍然都要有。

具體訊號：

| 訊號 | 不瑣碎（寫詳細） | 瑣碎（一句話帶過） |
|---|---|---|
| 檔案異動 | 有改到／新增／刪除檔案 | 完全沒動任何檔案 |
| 決策 | 做了會影響後續方向的選擇 | 沒有做任何選擇，純粹回應 |
| Status | `IN_PROGRESS` / `BLOCKED`（還有事沒完） | `DONE` 且沒有任何懸而未決 |
| 內容重複性 | 帶來新資訊 | 只是重複或確認前一輪已經記過的事 |

## Round Segments：單輪內的階段性記錄

一輪如果有好幾個明顯階段（先探索、再決策、再實作、再驗證），不要憋到最後才寫
一次 Summary／Handoff——中途 crash 會整個過程全部遺失。邊做邊在 User Input 和
收尾的 Summary／Handoff 之間追加 `### 段落 N - HH:MM` 子區塊，跟判斷
`Status: IN_PROGRESS` 同一套標準：「有意義的階段性結果」才寫，不是照時間或工具
呼叫次數機械觸發。不要把段落內容再抄進 Summary 或 Handoff。

另有一道保底：同一輪連續約 10 分鐘（可用 `/devlog-tracker:segment-watch <時間長度>`
調整）沒改 `.devlog/.round-current.md`，下一個工具會被 PreToolUse hook 擋住，先
Read `.devlog/.round-current.md` 再用 Edit／StrReplace 追加一段（**禁止**用 Write
覆寫整份檔）。

完整格式範例、寫入細則、跟 dynamic workflow／subagent 的例外情況，見
`${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/devlog-tracker/references/round-segments.md`。

## Reply Fold：把「Claude 提問、user 回答」記成同一個 Round

一輪如果是 Claude 用純文字結尾提出一個具體問題（不是用 `AskUserQuestion`
工具），下一則使用者訊息通常是答案、不是新話題——預設行為（每個
`UserPromptSubmit` 開新 `## Round`）會把這組問答硬拆成兩個不相關的 Round。
Reply Fold 讓它折進同一個 Round。

`AskUserQuestion` 在同一 turn 內問答，不用 fold、不要跑 `await-open.sh`；
但仍要用 `### 段落（AskUserQuestion）` 把問題與答案寫進本 Round，方便 L1
接手。細節見 `references/reply-fold.md`。

**提問前**（純文字跨 turn；結束 turn 之前）：先用 Edit 在 `### Summary` 之前插入一段
`### 段落（Claude 提問）` 記下問題原文，再跑
`${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/core/scripts/await-open.sh` 標記「下一則訊息大概是在
回答這個 Round」。使用者回答時 `round-start.sh` 會自動折成對應段落，不用手動
處理。連續多輪一問一答（例如 grilling）時不必每題重寫 Summary／Reply／Handoff／
Status，只有整場問答真正結束才收尾一次。

完整步驟、折疊格式、猜錯的處理、跟 task-notification／Span Mode／checkpoint
計數的關係，見 `${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/devlog-tracker/references/reply-fold.md`。

## Span Mode：橫跨多次自動續接的長任務

`/loop` 動態模式、`Workflow`、或任何被自己排程（`ScheduleWakeup`、背景 agent
完成通知）反覆喚醒、不是使用者手動打字觸發的長任務，如果每個自動 tick 都當一
輪強制寫，會逼出大量沒意義的紀錄或卡住整條自動化流程。只有**確定接下來會進入
一連串自動續接**時才開（一般互動式對話不需要，也不應該開），用
`/devlog-tracker:span` 建立 `.devlog/.span-open`，累積到門檻
（`max_silent_ticks`）才強制寫一次；崩潰最多漏記固定數量的 tick，不是整段 span。

JSON 格式、開關步驟、已知限制（分辨不出自動續接 vs 真人插話），見
`${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/devlog-tracker/references/span-mode.md`（設計動機
見 `docs/design/span-mode.md`）。

## Checkpoint Mode：定期摘要

跟 Span Mode 不同：Span 管「一輪內部/自動續接期間要不要強制寫」，Checkpoint
管「累積夠多輪之後，要不要插入一段橫跨多輪的摘要」，讓翻閱 devlog.md 的人不用
逐輪爬完才知道整體進度。`/devlog-tracker:start` 後全自動運作，累積約 20 輪
（可用 `/devlog-tracker:checkpoint <輪數>` 調整）沒寫 `## Checkpoint`，Stop
hook 會要求補一段。

運作機制、`/devlog-tracker:pause` 之後的行為，見
`${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/devlog-tracker/references/checkpoint-mode.md`
（設計動機見 `docs/design/checkpoint-mode.md`）。補寫時用固定三段：
`### 決策`／`### 待解問題`／`### 失敗嘗試`（格式與填寫規則見該 reference）。

## 壓縮歸檔：`/devlog-tracker:compact`

歸檔只在使用者下 `/devlog-tracker:compact` 時做，不會自動觸發（見 `commands/compact.md`）。
規則：

- 保留：專案摘要（如果有）、最近 5 輪、所有還沒 `DONE`（`IN_PROGRESS`/`BLOCKED`/`INTERRUPTED`）的輪次
- 其餘 `DONE` 的舊輪次：完整搬到 `.devlog/devlog.archive.md`（append，不覆寫既有歸檔）
- 只搬移，不刪除、不改寫內容

## 具名保存：`/devlog-tracker:keep`

掃描整份 `devlog.md`，把值得留名的主題段落一次分別**搬走**成 `.devlog/devlog.<name>.md`（也可只抽出一段，或合併成全部歷史一個檔）。這不是 compact：compact 把舊的 `DONE` 輪次 append 進 `devlog.archive.md`；keep 寫的是一個主題一個檔，且從不寫 archive。步驟見 `commands/keep.md`。不要自動觸發。

每次搬走都會在 `devlog.md` 尾端留一個 `## Kept 索引` 區塊（自動重建，永遠只有一份），
每個具名檔一行：`devlog.<name>.md`、搬走的 Round 範圍、`kept_at` 時間戳、一句主題描述
（`keep-move.sh --desc`，`commands/keep.md` 批次確認時生成的那句；沒帶 `--desc` 或既存
的舊索引行就沒有這一段）。SessionStart 注入的接手摘要會帶上這個索引（不是具名檔的內容），
讓「哪個主題被搬去哪個檔」不用翻完整份 `devlog.md` 或憑印象猜檔名
（`docs/design/devlog-as-ssot-assessment.md` Phase 3）。

## 整理所有 devlog：`/devlog-tracker:keep-all`

keep 只整理目前分支的主檔；keep-all 一次整理 `.devlog/` 裡**所有** devlog 檔：目前分支的
主檔、其他分支的 `devlog.<branch>.md`、`devlog.archive.md`，以及既有的具名檔。Round 依時間
拿到全域編號，Claude 跨檔依主題重新分段、一次列出建議，確認後 `core/scripts/keep-all.sh`
整批執行（全有或全無，先備份到 `.devlog/.keep-all-backup/`）。既有 kept 檔的 Round 必須全部
重新分配；各分支最後一個 `DONE` 之後的未完成尾巴與開著的那一輪不搬；搬空的分支檔（分支非 `active`）會刪除，目前主檔與 `devlog.md` 不刪。
新索引行寫進目前分支主檔的 `## Kept 索引`。需要 Node。步驟見 `commands/keep-all.md`。不要自動觸發。

## 接續具名保存：`/devlog-tracker:resume <name>`

需要重啟具名主題時，用 resume 讀取 `.devlog/devlog.<name>.md` 的最後一輪與
Handoff。核對用 `commands/continue.md` 步驟 5.1–5.2（不要跟著做 5.3 立刻開工）；
`IN_PROGRESS`／`INTERRUPTED`／`BLOCKED` 都要核對，提出接續後等使用者確認才做下一步。
`DONE` 不核對、不開工。新工作仍記錄到 `devlog.md`，不要改寫 keep 檔。SessionStart 不會自動注入具名檔。
步驟見 `commands/resume.md`。

## 跨檔總覽：`/devlog-tracker:overview`

純讀取，不核對工作區、不等確認（跟 `/devlog-tracker:lessons` 一樣的唯讀風格）。用
`core/scripts/kept-list.sh` 解析 `## Kept 索引` 取出所有 `devlog.<name>.md` 檔名（含存在性
檢查，磁碟上被手動刪掉的 ghost row 只提一句，不嘗試修復），讀完所有存在的檔案後在對話裡
產出兩塊：跨主題敘事總覽，以及一節「可能該進 `CLAUDE.md` 的規範候選」（挑得出來才輸出，
格式貼近 `CLAUDE.md` 條列寫法方便複製）。不寫入任何檔案，包含 `CLAUDE.md` 本身。步驟見
`commands/overview.md`。

## 跨檔搜尋：`/devlog-tracker:search <關鍵字>`

純讀取，不核對工作區、不等確認（跟 overview／lessons 一樣的唯讀風格）。用
`core/scripts/search-devlog.sh` 掃過 `.devlog/devlog*.md`（主檔、archive、keep、lessons、
分支檔一個 glob 涵蓋），做不分大小寫的固定字串比對，回報命中檔、最近 `##`／`###` 標題與
行內容。自然語言查詢由 Claude 先抽出關鍵片語再丟給腳本；不另建 index、不做 embedding。
讀完命中後**用自己的話**回答使用者在問什麼，必要時附檔名／標題／行號當出處——不要把腳本
原始輸出整段貼當主回答。不寫入任何檔案。步驟見 `commands/search.md`。

## Lessons Mode：開發歷程教訓（預設關閉，非架構知識庫）

跟 Checkpoint／Span 不同，管的是「開發**過程**踩過的坑」，不是進度或架構——架構
決策的 SSOT 永遠是 `docs/design/*.md`。預設關閉，隸屬主開關（沒下過
`/devlog-tracker:start` 會被拒絕）。開著時有兩種自我判斷訊號考慮記一筆：這輪
`Status` 從 `BLOCKED` 解開、你自行判斷這輪明顯繞了一圈——這兩種完全仰賴你自己
想起來，hook 不強制、不追蹤。另外有兩種機制性訊號，由 hook 累積計數、達門檻只印
一句顧問式建議（預設 3 次，`/devlog-tracker:lessons-drift <次數>` 可調，兩種共用
同一個門檻）：工作區漂移（宣稱跟實際不符）累積達門檻、或 Status 是 `BLOCKED` 的
輪次累積達門檻；另外「上一輪從 `BLOCKED` 解開」這個轉變，下一輪開始時 hook 也會
機械印一句提示（不經過門檻計數，偵測到就印）。以上全部都完全不 hook 強制寫入
本身——寫不寫都不影響這一輪能不能收尾。

若這輪任務是透過 Agent 工具派 sub agent，或用 Workflow 工具跑多階段 pipeline，一樣可能
踩到值得記的坑，只是沒有 Round／Status 可比對訊號；讀完 sub agent／workflow 的最終回報後
自我判斷（例如 verify 推翻了它先前的 fix、它自陳繞了一圈、多個 agent 重複卡在同一種問題、
或成果被打回票要求重做），值得的話一樣呼叫 `lessons-append.sh`。Claude Code 與 Codex 的
`SubagentStart` hook 會在 sub agent 開始時注入 `lessons-append.sh` 的絕對路徑用法，讓它自行判斷
是否記錄。Claude Code 的前景 agent 回來或背景任務通知到達時，還會顯示 `[Lessons Mode 提示]`
（`failed`／`killed` 另算進共用計數器）；Codex 讀完回報後自行檢查上述訊號。sub agent 已記過
的不用重複記。

寫法、per-topic 存檔規則、索引重建、機制性訊號細節，見
`${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/devlog-tracker/references/lessons-mode.md`（完整
設計見 `docs/design/lessons-mode.md`）。

## 無條件清空：`/devlog-tracker:clean`

把 `devlog.md` 整份清空（含專案摘要與所有 Round 歷史），不搬移、不備份，不可復原。跟 compact／keep 不一樣：那兩個都是「搬去別的檔案保留」，clean 是真的丟棄。執行前一定要先問使用者、拿到明確的「清空」才動手；只有目前開著的那一輪會留下（若有開著，內容讀自 `.devlog/.round-current.md`，不是已經清空的 `devlog.md`），重編成 `## Round 1`。步驟見 `commands/clean.md`。不要自動觸發。
