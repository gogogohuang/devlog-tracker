---
name: devlog-tracker
description: 在專案的 .devlog/devlog.md 維護逐輪對話紀錄。使用者下 /devlog-tracker:start 後 Stop hook 強制每輪寫入；SessionStart 在 startup / resume / compact / fork 注入進度，/clear 不注入；要接續用 /devlog-tracker:continue。當使用者提到「devlog-tracker」「.devlog/devlog.md」「/devlog-tracker:continue」或明確要寫／接續這份紀錄時使用。
---

# Devlog Tracker（簡化版）

參考 agfnow/agentflow 的 devlog 基礎協定做的簡化版，只保留「逐輪對話紀錄」這一層，
不含原版的 10 步驟 SDD pipeline、多模型對抗審查、external worker 外包等進階機制。

## 核心原則

devlog.md 是**跨 session 交接連續性**（決策軌跡、目前卡點、下一步）的 single source of truth，
不是整個專案的單一真相來源：程式碼／檔案狀態的真相仍是 git（`#### 工作區` 是收尾當下的已核對快取：
`IN_PROGRESS`／`BLOCKED` 時 Stop hook 一律對過 live git，`DONE` 若「檔案」有內容也對過；接手時樹可能已變，`continue`／`resume`
仍以實際工作樹為準，見 `docs/design/continue.md`）；完整逐字過程的真相是對話 transcript（`/clear` 後不存在）；設計
決策的真相是 `docs/design/*.md`。使用者在裡面許願、Claude 也在裡面回報進度與結果——取代「終端機
一 clear 就沒了」的對話記錄，讓工作可以隨時中斷、隨時接續。

## 寫進 devlog 不等於講給使用者聽

`### Summary`／`### Handoff`／`### 段落`／`## Checkpoint` 這些內容是寫給「下一個
讀 devlog.md 的人」看的，不是講給正在對話的使用者聽的——這是兩件不同的事，收尾時
用 Edit／Write 工具**安靜地**寫進 `.devlog/devlog.md`（工具呼叫本身不會顯示給
使用者），寫完之後**不要**在聊天回覆裡再提這件事。

具體來說，這輪收尾的聊天回覆裡：

- **不要**出現「devlog」「Round」「Summary」「Handoff」「Status」「這一輪」這些字，
  也不要說「已寫入」「已補上」「已記錄」「收尾完成」之類的動作旁白——使用者看不到
  你剛剛用工具做了什麼，講這些等於自己報告一件使用者沒問過的事，是雜訊。
- **不要**把剛寫進 Handoff／Summary 的內容（決策、下一步、現況）換句話再講一次。
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
`devlog.md` 還真的改了別的檔案（例如 README.md、程式碼），結尾照常給一兩句
話總結改了什麼、下一步是什麼——但 `.devlog/devlog.md` 這個異動本身**不算
在「改了什麼」裡面，永遠不要提**，因為那是記錄動作本身、不是產出。舉例：
這輪同時修了 `README.md` 又寫了 `devlog.md`，結尾只講「README.md 已更新
成...」，不要接著再講「devlog 也已更新／已補上這輪的 Summary/Handoff」——
後面這句要整句刪掉，不是縮短。

## 檔案位置

- 主檔：`.devlog/devlog.md`
- 歸檔：`.devlog/devlog.archive.md`
- 具名保存：`.devlog/devlog.<name>.md`（`/devlog-tracker:keep` 搬走的主題檔；SessionStart 不讀這些檔）

第一次使用時，若 `.devlog/` 不存在就建立它。

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

1. 使用者送出新訊息時，`UserPromptSubmit` hook（`hooks/scripts/round-start.sh`）
   若開關開著，就在 `.devlog/devlog.md` 尾端追加這一輪的 skeleton（`### User Input`
   + `Status: IN_PROGRESS`），並寫 `.devlog/.round-open`。`.turn-start` 雜湊是
   **寫完 skeleton 之後**才拍的，所以 Stop 仍能判斷 Claude 有沒有再補收尾。
2. Claude 編輯**同一個** Round：不要再 append 一個新的 `## Round`。不要改 User Input
   （除非裡面是 hook 的 `（無 prompt）` 占位）。補上 `### Summary` / `### Handoff`，
   把 Status 改成 `DONE` / `IN_PROGRESS` / `BLOCKED`。
3. `Stop` hook（`hooks/scripts/enforce-devlog.sh`）若雜湊沒變、或最後一個 Round
   缺少 `### Summary` / `### Handoff`，就用 exit code 2 擋下來。通過則刪掉
   `.round-open`。

好處：就算工作做到一半被中斷（下一輪還沒開始就被使用者關掉、或換 session），
只要**上一輪有正常結束過**，devlog.md 就一定留有當時的 Status（多半是 `IN_PROGRESS`
或 `BLOCKED`）可以接續——這跟「plan 是否完成」完全無關，純粹綁在「這一輪有沒有結束」
這個事件上。

需要誠實說明的邊界：User Input 在送出當下就已經在 `devlog.md`。正常結束時 Stop 仍保證有 Summary / Handoff。
意外中斷會把同一塊標成 `INTERRUPTED`（process 被殺、或 mid-turn 取消時，Status 通常要等
**下一則訊息**或**下次 SessionStart（startup / resume / clear / fork）**才補上）。
`PostToolUseFailure` 的 `is_interrupt` 若有觸發，只是 best-effort 的額外路徑，不能當成 Esc
會立刻蓋章。中間沒寫成 `### 段落` 的過程仍會丟——Segment Watch 只在還有下一個工具呼叫時催促。

### 兩個穩健性設計（參考 agfnow/agentflow 的 stop-hook.js）

- **loop guard**：`enforce-devlog.sh` 一開始會讀 stdin 的 `stop_hook_active` 欄位——這是
  Claude Code 官方標準欄位，代表「這輪已經被本支 hook 擋下來一次、Claude 正在重跑」，
  此時直接放行，不會一直卡住同一輪。Claude Code 本身也有連續擋 8 次的上限保護，這是多
  一層保險。
- **fail-open**：三支 hook 腳本都不用 `set -e`，每一步可能失敗的地方（讀不到檔案、雜湊
  算不出來）都明確接住、失敗就直接放行。這些腳本的職責是「檢查」，不該因為自己的臭蟲
  就意外把使用者的 session 卡死。

更新（Span Mode 之後）：agentflow 的 Stop hook 會依「這一輪是不是還在進行中」
放寬檢查強度，這裡原本認為 Claude Code 原生的「一個使用者訊息 = 一輪」架構沒有
對應的地方可以搬這個設計過來。後來為了支援 `/loop`／`Workflow` 這類會被自動
排程反覆喚醒的長任務，加了上面的 Span Mode，算是這個設計的一個窄化版本——只在
Claude 主動宣告「接下來會有一串自動續接」時才放寬，且用 tick 計數做安全閥，
不是像 agentflow 那樣泛用地判斷「這輪是否還在進行中」。一般互動式對話仍然是
完整的「一個訊息 = 一輪」強制模式，沒有變。

## 自動接續與 `/clear`

這個 plugin 內建一個 SessionStart hook（`hooks/hooks.json` + `hooks/scripts/session-start-devlog.sh`），
matcher 設為 `startup|resume|clear|compact|fork`。**開新 session、resume、`/compact`、`/fork`**
時會自動讀檔注入；**`/clear` 不會注入**——對話清空就是空的。

自動注入時：

1. 腳本讀取 `.devlog/devlog.md`，注入最後一個 `## Checkpoint`（若有）、最後一個 `## Kept 索引`（若有；不是具名檔內容），加上最近 2 輪的 Summary / Handoff / Status（沒有 Summary 的 skeleton 才帶 User Input）
2. 印到 stdout，Claude Code 會把這段文字當成這次 session 的 additionalContext 自動注入
3. Claude 收到這段 context 後，開場就已經知道目前進度

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
「接續」「繼續上一題」）。讀 `devlog.md`，**先核對**最後一輪 Handoff 的 `#### 工作區`
（跑步驟 5.1，編成同一格式再對），再依「下一步」開工。有快照但不符才先寫 `### 段落`；
沒有快照（舊 Round、`INTERRUPTED` stub）直接以實際狀態為準，不用寫。步驟見 `commands/continue.md`。
`DONE` 就說明上一題已結束、等新需求，不核對。`BLOCKED`：缺的外部輸入仍缺就停，已經出現就做；
不要用 git 相不相符當作缺件已到。SessionStart 注入的摘錄若讓你要動手做「下一步」，同樣先核對。
同一條對話的下一則訊息也一樣：UserPromptSubmit 若發現上一輪 `#### 工作區` 跟 live git 不符，會注入說明並在 PreToolUse 擋住其他工具，直到這一輪寫了含實際快照的 `### 段落`。Span 安靜 tick 與 task-notification 不擋。`DONE` 一律不擋（跟 Stop hook 不同：Stop 在 `DONE` 有「檔案」時會機器核對，但這裡管的是「上一輪的宣稱還能不能拿來接續下一步」——`DONE` 沒有下一步可接，即使當初有檔案也不用重查）。沒呼叫任何工具的純文字回覆不會碰到 PreToolUse，仍應先核對再依實際工作樹行動。擋著的時候，唯讀的 `git status`／`diff`／`log`／`show`／`rev-parse`（不含任何 shell 串接符號）仍可執行，方便自行核對「宣稱 vs 實際」再動手寫段落。
不要自動觸發。`/devlog-tracker:start` 只對進度，不開工、不核對。

## 每一輪的紀錄格式

hook 已在送出時寫好 User Input；Claude **編輯最後一個 Round**，不要為同一則使用者訊息再新增一個 `## Round`：

```markdown
## Round <N> — <ISO 8601 時間戳，含時區>

### User Input
<使用者這輪的輸入，貼近原話，保留關鍵細節，不用強制逐字照抄>

### Summary
<2–4 句，給人掃：這輪結論、有沒有卡住。不要寫檔案路徑、commit hash、skill 名稱、逐步指令>

### Handoff
#### 決策
<影響後續方向的選擇與理由。沒做選擇就整節省略>

#### 檔案
<機器可核對格式，見下方「檔案 machine-verify」：零個以上 `commit <hash>：` 區塊（依時間序），
加上最多一個 `尚未 commit：` 區塊，各自帶 `新增：`/`修改：`/`刪除：` 分類行（無則省略該行）。
沒動檔就整節省略>

#### 工作區
<IN_PROGRESS／BLOCKED 必寫；DONE 若上面「檔案」有內容（宣稱動過／commit 過檔案）也必寫，
Stop hook 會機器核對；DONE 且「檔案」整節省略時，工作區才能跟著省略。收尾前跑 git 再寫，見下方格式>

#### 現況
<任務做到哪、卡在哪。git 快照寫在「工作區」，不要寫這裡。幾乎每輪都該有>

#### 下一步
<下一輪第一件具體要做的事（路徑、指令、要載入的 skill）。
IN_PROGRESS／BLOCKED 必寫；DONE 且沒有後續就整節省略>

### Status
DONE | IN_PROGRESS | BLOCKED | INTERRUPTED
```

Round 編號：讀取檔案中最後一個 `## Round <N>`，本輪用 N+1；檔案不存在就從 Round 1 開始。

寫入原則：
- **User Input 預設貼近使用者原話，但保留彈性，不強制逐字照錄。** 目標是讓人「只讀這份
  檔案、不用翻對話紀錄」就能接續開發，所以要保留原始措辭裡的關鍵細節（用詞、並列條件、
  隨口補充的例外情況），但不用機械式地一字不漏照抄——內容太長、太雜（例如夾雜大段貼上的
  log 或程式碼）時，可以留原文最相關的部分、把明顯的雜訊留在原處摘要帶過，怎麼拿捏由
  Claude 自己判斷，不用每次都整段複製。
- **兩個讀者拆開：** `Summary` 只給人掃；`Handoff` 只給下一輪 Claude 接手。同一件事不要兩邊複述。
- Handoff 小節順序固定（決策 → 檔案 → 工作區 → 現況 → 下一步），Stop hook 會檢查已出現的小節
  順序有沒有錯、有沒有重複（不檢查內容對不對）。沒發生的整節省略，不要寫「無」。
  `現況` 幾乎每輪都該有。`工作區` 與 `下一步` 在 `IN_PROGRESS`／`BLOCKED` 必寫；`DONE` 且沒有後續就整節省略——
  但 `DONE` 若 `檔案` 有內容（宣稱動過／commit 過檔案），`工作區` 一樣必寫且會被 Stop hook 機器核對，
  避免「已 commit 完成」卻其實沒 commit 這種宣稱跟實際不符沒人發現。
  `下一步` 要具體到下一輪打開就能做，寫「繼續完成」不算完成。
- **`工作區` 是收尾當下的 git 快照，給下一輪核對用。** 寫之前跑 `git status --short`、`git rev-parse --abbrev-ref HEAD`、`git rev-parse --short HEAD`，照輸出寫。`abbrev-ref` 為 `HEAD` 時用 detached 格式；`rev-parse --short HEAD` 失敗但 `git symbolic-ref --short HEAD` 抓得到分支名（尚無 commit，例如剛 `git init`）用 unborn 格式；兩者都失敗才是非 git。髒檔是整棵樹的未提交，不必跟「檔案」那輪 delta 相同。格式：
  - 乾淨：`main @ a1b2c3d，工作樹乾淨`（一行）
  - 有未提交：第一行 `feat/foo @ a1b2c3d`，第二行 `未提交：src/a.ts, hooks/foo.sh`
  - 非 git：一行 `非 git 工作區`
  - detached 乾淨：`HEAD detached @ a1b2c3d`（一行）
  - detached 有未提交：第一行 `HEAD detached @ a1b2c3d`，第二行 `未提交：src/a.ts, hooks/foo.sh`
  - unborn（尚無 commit）乾淨：`main @ (尚無 commit)，工作樹乾淨`（一行）
  - unborn（尚無 commit）有未提交：第一行 `main @ (尚無 commit)`，第二行 `未提交：src/a.ts, hooks/foo.sh`
  （七種格式的機器生產者只有 `hooks/scripts/workspace-snapshot.sh`。寫入照上面手寫；Stop 用同一 function 核對。改格式時改 SKILL 與該腳本，不要在 continue.md 再抄一份。）
  `INTERRUPTED` stub 不寫這一節。`IN_PROGRESS`／`BLOCKED` 收尾時，Stop hook 會自己算一次
  即時 git 快照，跟這一節逐字比對，不符就擋下來並印出正確內容（`hooks/scripts/workspace-snapshot.sh`，
  docs/design/devlog-as-ssot-assessment.md Phase 1）；`DONE` 若「檔案」有內容一樣核對——只有
  沒動檔的 `DONE` 與 `INTERRUPTED` 不受影響。
  接手跑 `workspace-snapshot.sh`（`PLUGIN_ROOT` 同其他指令），stdout 就是要對的快照，不要手編（continue／fallback 見 `commands/continue.md` 步驟 5；resume 只做 5.1–5.2，等確認才做下一步）。腳本找不到才退回上面七種格式手編。
- **`檔案` 是機器可核對的區塊格式（devlog ssot Phase 4）。** 零個以上 `commit <hash>：` 區塊
  （commit 短 hash，依時間序），每個後面接最多三行分類（`新增：`/`修改：`/`刪除：`，逗號分隔路徑，
  沒有就省略那行）；最多一個 `尚未 commit：` 區塊，格式相同。一輪可以先 commit 一部分、後面
  繼續改，兩種區塊可以並存。Stop hook 對 `commit` 區塊做逐字精確核對（含分類），對
  `尚未 commit` 區塊只核對「宣稱的路徑是否真的在目前髒檔清單裡」（不核對分類，也不要求
  涵蓋所有髒檔——跨輪殘留、還沒 commit 的舊檔案不算這輪漏列）。Rename 一律回報成
  刪除+新增，不是第四類。`.devlog/` 路徑不算進比對。看不懂的行（沒有照這個格式寫）會被擋下來，
  不是 fail-open——這是 Claude 該產生的格式，不是可有可無的宣告。細節見
  `docs/design/files-verify.md`（`hooks/scripts/files-snapshot.sh`）。
- Handoff 只寫已發生的事；未來式只允許出現在「下一步」。
- `Status` 只寫 `DONE`、`IN_PROGRESS`、`BLOCKED`、`INTERRUPTED` 其中一個，不要在下面再附「接下來要做什麼」
  （那句搬進 Handoff 的「下一步」）。`IN_PROGRESS` = 還能做；`BLOCKED` = 缺外部輸入；
  `DONE` = 這輪請求已結束。**例外只有 hook 自動蓋 `INTERRUPTED` 時**：`close-open-round.sh`
  會在下面多印一行 `[reason: ...]`（例如 `[reason: dangling:next_prompt]`），這是 hook 自己的
  除錯代號、用方括號標記成內部 metadata，特意不用 HTML 註解（會被 Markdown 渲染器整段隱藏，
  之後要 debug 反而看不到），不算違反「只寫一個值」——看到這行不用當成錯誤，Claude 也不用去動它。
- `INTERRUPTED` 只由 hook 在意外中斷時寫上（非 usage 的 API 錯誤、SessionEnd、
  下次 SessionStart（startup / resume / clear / fork）或下一則訊息發現 `.round-open` 還在）。
  mid-turn 取消（例如 Esc）通常也是走這條延後路徑；`PostToolUseFailure` 的 `is_interrupt`
  若有觸發只是 best-effort，不能當成一定會立刻蓋章。Claude 正常收尾時不要自己選這個值。
  usage 用光（`rate_limit` / `billing_error` / `account_on_hold`）不標中斷。
- 每輪一個區塊，不要把多輪內容合併寫成一個 Round。
- 不要另外開欄位列「這輪用了哪些 skill」——那是稽核用途，跟接續開發沒有直接關係。只有
  當接續動作**必須**重新載入某個特定 skill 才能正確接手時，才把 skill 名稱寫進 Handoff
  「下一步」裡。

Stop hook 會檢查最後一個 Round 是否同時有 `### Summary` 與 `### Handoff`、兩者底下有內容、`### Status` 是四個合法值之一，已出現的 Handoff 小節順序與不重複，以及 `IN_PROGRESS`／`BLOCKED` 時 Handoff 有「下一步」且不是純黑名單空話（例如整節只寫「繼續完成」，見 `docs/design/next-step-blacklist.md`；這是字串比對，不是語意評分）；`#### 工作區` 跟 hook 算出的 git 快照相符——`IN_PROGRESS`／`BLOCKED` 一律核對，`DONE` 則只在「檔案」有內容時才核對（瑣碎、沒動檔的 DONE 輪不受影響）；`#### 檔案` 非空時，hook 也會核對它是否符合實際 git 變更（commit 區塊精確核對，未 commit 區塊單向核對，見上方「檔案 machine-verify」）。
新開的 Round 兩個標題都要有，瑣碎輪也不例外。

### 怎麼判斷這輪該寫多細（瑣碎程度）

「每輪都要記錄」管的是**要不要留下這一輪的痕跡**，瑣碎程度管的是**該寫多細**，這是兩件
不同的事——瑣碎不代表可以跳過不記，只代表這輪該寫得短。

判斷測試：**如果把這一輪從 devlog 刪掉，之後光讀檔案接續工作，會不會漏掉重要資訊？**
會漏掉就不瑣碎，要完整寫；不會漏掉（純確認、閒聊、使用者只回「好」「謝謝」、沒有產生任何
實質變化或懸而未決的事）就是瑣碎，但**還是要有這個 Round 區塊**，只是 Summary 一句話、
Handoff 只留「現況」一句（沒有「工作區」），Status 多半 `DONE`。兩個標題仍然都要有。

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
調整）沒改 `devlog.md`，下一個工具會被 PreToolUse hook 擋住，先 Read 再用
Edit／StrReplace 追加一段（**禁止**用 Write 覆寫整份檔）。

完整格式範例、寫入細則、跟 dynamic workflow／subagent 的例外情況，見
`${CLAUDE_PLUGIN_ROOT}/skills/devlog-tracker/references/round-segments.md`。

## Reply Fold：把「Claude 提問、user 回答」記成同一個 Round

一輪如果是 Claude 用純文字結尾提出一個具體問題（不是用 `AskUserQuestion`
工具），下一則使用者訊息通常是答案、不是新話題——預設行為（每個
`UserPromptSubmit` 開新 `## Round`）會把這組問答硬拆成兩個不相關的 Round。
Reply Fold 讓它折進同一個 Round。

**提問前**（結束 turn 之前）：先用 Edit 在 `### Summary` 之前插入一段
`### 段落（Claude 提問）` 記下問題原文，再跑
`${CLAUDE_PLUGIN_ROOT}/hooks/scripts/await-open.sh` 標記「下一則訊息大概是在
回答這個 Round」。使用者回答時 `round-start.sh` 會自動折成對應段落，不用手動
處理。連續多輪一問一答（例如 grilling）時不必每題重寫 Summary／Handoff／
Status，只有整場問答真正結束才收尾一次。

完整步驟、折疊格式、猜錯的處理、跟 task-notification／Span Mode／checkpoint
計數的關係，見 `${CLAUDE_PLUGIN_ROOT}/skills/devlog-tracker/references/reply-fold.md`。

## Span Mode：橫跨多次自動續接的長任務

`/loop` 動態模式、`Workflow`、或任何被自己排程（`ScheduleWakeup`、背景 agent
完成通知）反覆喚醒、不是使用者手動打字觸發的長任務，如果每個自動 tick 都當一
輪強制寫，會逼出大量沒意義的紀錄或卡住整條自動化流程。只有**確定接下來會進入
一連串自動續接**時才開（一般互動式對話不需要，也不應該開），用
`/devlog-tracker:span` 建立 `.devlog/.span-open`，累積到門檻
（`max_silent_ticks`）才強制寫一次；崩潰最多漏記固定數量的 tick，不是整段 span。

JSON 格式、開關步驟、已知限制（分辨不出自動續接 vs 真人插話），見
`${CLAUDE_PLUGIN_ROOT}/skills/devlog-tracker/references/span-mode.md`（設計動機
見 `docs/design/span-mode.md`）。

## Checkpoint Mode：定期摘要

跟 Span Mode 不同：Span 管「一輪內部/自動續接期間要不要強制寫」，Checkpoint
管「累積夠多輪之後，要不要插入一段橫跨多輪的摘要」，讓翻閱 devlog.md 的人不用
逐輪爬完才知道整體進度。`/devlog-tracker:start` 後全自動運作，累積約 20 輪
（可用 `/devlog-tracker:checkpoint <輪數>` 調整）沒寫 `## Checkpoint`，Stop
hook 會要求補一段。

運作機制、補寫格式、`/devlog-tracker:pause` 之後的行為，見
`${CLAUDE_PLUGIN_ROOT}/skills/devlog-tracker/references/checkpoint-mode.md`
（設計動機見 `docs/design/checkpoint-mode.md`）。

## 壓縮歸檔：`/devlog-tracker:compact`

歸檔不再是自動觸發，而是使用者主動下 `/devlog-tracker:compact` 指令時才做（見 `commands/compact.md`）。
規則：

- 保留：專案摘要（如果有）、最近 5 輪、所有還沒 `DONE`（`IN_PROGRESS`/`BLOCKED`/`INTERRUPTED`）的輪次
- 其餘 `DONE` 的舊輪次：完整搬到 `.devlog/devlog.archive.md`（append，不覆寫既有歸檔）
- 只搬移，不刪除、不改寫內容

## 具名保存：`/devlog-tracker:keep`

掃描整份 `devlog.md`，把值得留名的主題段落一次分別**搬走**成 `.devlog/devlog.<name>.md`（也可只抽出一段，或合併成全部歷史一個檔）。這不是 compact：compact 把舊的 `DONE` 輪次 append 進 `devlog.archive.md`；keep 寫的是一個主題一個檔，且從不寫 archive。步驟見 `commands/keep.md`。不要自動觸發。

每次搬走都會在 `devlog.md` 尾端留一個 `## Kept 索引` 區塊（自動重建，永遠只有一份），
每個具名檔一行：`devlog.<name>.md`、搬走的 Round 範圍、`kept_at` 時間戳。SessionStart
注入的接手摘要會帶上這個索引（不是具名檔的內容），讓「哪個主題被搬去哪個檔」不用翻完整份
`devlog.md` 或憑印象猜檔名（`docs/design/devlog-as-ssot-assessment.md` Phase 3）。

## 接續具名保存：`/devlog-tracker:resume <name>`

需要重啟具名主題時，用 resume 讀取 `.devlog/devlog.<name>.md` 的最後一輪與
Handoff。核對用 `commands/continue.md` 步驟 5.1–5.2（不要跟著做 5.3 立刻開工）；
`IN_PROGRESS`／`INTERRUPTED`／`BLOCKED` 都要核對，提出接續後等使用者確認才做下一步。
`DONE` 不核對、不開工。新工作仍記錄到 `devlog.md`，不要改寫 keep 檔。SessionStart 不會自動注入具名檔。
步驟見 `commands/resume.md`。

## Lessons Mode：開發歷程教訓（預設關閉，非架構知識庫）

跟 Checkpoint／Span 不同，管的是「開發**過程**踩過的坑」，不是進度或架構——架構
決策的 SSOT 永遠是 `docs/design/*.md`。預設關閉，隸屬主開關（沒下過
`/devlog-tracker:start` 會被拒絕）。開著時只有兩種訊號考慮記一筆：這輪 `Status`
從 `BLOCKED` 解開，或你自行判斷這輪明顯繞了一圈——完全不 hook 強制，寫不寫都不
影響這一輪能不能收尾。

寫法、per-topic 存檔規則、索引重建，見
`${CLAUDE_PLUGIN_ROOT}/skills/devlog-tracker/references/lessons-mode.md`（完整
設計見 `docs/design/lessons-mode.md`）。

## 無條件清空：`/devlog-tracker:clean`

把 `devlog.md` 整份清空（含專案摘要與所有 Round 歷史），不搬移、不備份，不可復原。跟 compact／keep 不一樣：那兩個都是「搬去別的檔案保留」，clean 是真的丟棄。執行前一定要先問使用者、拿到明確的「清空」才動手；只有目前開著的那一輪會留下，重編成 `## Round 1`。步驟見 `commands/clean.md`。不要自動觸發。
