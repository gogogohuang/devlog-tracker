---
name: devlog-tracker
description: 在專案的 .devlog/devlog.md 維護逐輪對話紀錄。使用者下 /devlog-tracker:start 後 Stop hook 強制每輪寫入；SessionStart 在 startup / resume / compact / fork 注入進度，/clear 不注入；要接續用 /devlog-tracker:continue。當使用者提到「devlog-tracker」「.devlog/devlog.md」「/devlog-tracker:continue」或明確要寫／接續這份紀錄時使用。
---

# Devlog Tracker（簡化版）

參考 agfnow/agentflow 的 devlog 基礎協定做的簡化版，只保留「逐輪對話紀錄」這一層，
不含原版的 10 步驟 SDD pipeline、多模型對抗審查、external worker 外包等進階機制。

## 核心原則

devlog.md 是 single source of truth。使用者在裡面許願、Claude 也在裡面回報進度與結果——
取代「終端機一 clear 就沒了」的對話記錄，讓工作可以隨時中斷、隨時接續。

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
- 使用者下 `/devlog-tracker:continue`：讀現有 devlog，依最後一輪 Handoff 的下一步接著做（見
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

1. 腳本讀取 `.devlog/devlog.md`，注入最後一個 `## Checkpoint`（若有）加上最近 2 輪的 Summary / Handoff / Status（沒有 Summary 的 skeleton 才帶 User Input）
2. 印到 stdout，Claude Code 會把這段文字當成這次 session 的 additionalContext 自動注入
3. Claude 收到這段 context 後，開場就已經知道目前進度

`/clear` 時 hook 仍可能把殘留的開著 Round 標成 `INTERRUPTED`，但 stdout 什麼都不印。
之後只有使用者下 `/devlog-tracker:continue`，或明確說「continue」「接續」「繼續上一題」時，
才讀 `.devlog/devlog.md` 並依 Handoff 下一步接著做（見 `commands/continue.md`）。
一般新請求當成空白對話，不要先讀檔接舊工作。`/devlog-tracker:start` 只對進度，不開工。

找不到 `.devlog/devlog.md` 時 hook 直接 exit 0，不輸出任何東西，不會干擾沒有用 devlog 的專案。

如果 hook 在 startup / resume / fork 沒有生效（例如使用者不是用 Claude Code、或 hook 因為某些
環境問題沒跑），Claude 仍應主動：使用者在已有 devlog.md 的專案裡提出一般開發需求時，先讀一次
`.devlog/devlog.md` 最後幾輪再接手。這個 fallback **不適用於 `/clear` 之後**——clear 之後沒有
說 continue，就不要讀檔。

## 接續：`/devlog-tracker:continue`

`/clear` 之後要接著做上一題，下 `/devlog-tracker:continue`（或明確說「continue」
「接續」「繼續上一題」）。讀 `devlog.md`，依最後一輪 Handoff 的下一步立刻開工。
`DONE` 就說明上一題已結束、等新需求；`BLOCKED` 就說明缺什麼、不要發明輸入。
步驟見 `commands/continue.md`。不要自動觸發。`/devlog-tracker:start` 只對進度，不開工。

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
<新增／修改／刪除的路徑；有 commit 就寫 hash 或說明沒 commit。沒動檔就整節省略>

#### 現況
<工作區現在的實際狀態，讓下一輪不用重探。幾乎每輪都該有>

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
- Handoff 四個小節順序固定（決策 → 檔案 → 現況 → 下一步）。沒發生的整節省略，不要寫「無」。
  `現況` 幾乎每輪都該有。`下一步` 在 `IN_PROGRESS`／`BLOCKED` 必寫，且要具體到下一輪打開就能做，
  不要寫「繼續完成」。
- Handoff 只寫已發生的事；未來式只允許出現在「下一步」。
- `Status` 只寫 `DONE`、`IN_PROGRESS`、`BLOCKED`、`INTERRUPTED` 其中一個，不要在下面再附「接下來要做什麼」
  （那句搬進 Handoff 的「下一步」）。`IN_PROGRESS` = 還能做；`BLOCKED` = 缺外部輸入；
  `DONE` = 這輪請求已結束。
- `INTERRUPTED` 只由 hook 在意外中斷時寫上（非 usage 的 API 錯誤、SessionEnd、
  下次 SessionStart（startup / resume / clear / fork）或下一則訊息發現 `.round-open` 還在）。
  mid-turn 取消（例如 Esc）通常也是走這條延後路徑；`PostToolUseFailure` 的 `is_interrupt`
  若有觸發只是 best-effort，不能當成一定會立刻蓋章。Claude 正常收尾時不要自己選這個值。
  usage 用光（`rate_limit` / `billing_error` / `account_on_hold`）不標中斷。
- 每輪一個區塊，不要把多輪內容合併寫成一個 Round。
- 不要另外開欄位列「這輪用了哪些 skill」——那是稽核用途，跟接續開發沒有直接關係。只有
  當接續動作**必須**重新載入某個特定 skill 才能正確接手時，才把 skill 名稱寫進 Handoff
  「下一步」裡。

Stop hook 會檢查最後一個 Round 是否同時有 `### Summary` 與 `### Handoff`、兩者底下有內容、`### Status` 是四個合法值之一，以及 `IN_PROGRESS`／`BLOCKED` 時 Handoff 有「下一步」。
新開的 Round 兩個標題都要有，瑣碎輪也不例外。

### 怎麼判斷這輪該寫多細（瑣碎程度）

「每輪都要記錄」管的是**要不要留下這一輪的痕跡**，瑣碎程度管的是**該寫多細**，這是兩件
不同的事——瑣碎不代表可以跳過不記，只代表這輪該寫得短。

判斷測試：**如果把這一輪從 devlog 刪掉，之後光讀檔案接續工作，會不會漏掉重要資訊？**
會漏掉就不瑣碎，要完整寫；不會漏掉（純確認、閒聊、使用者只回「好」「謝謝」、沒有產生任何
實質變化或懸而未決的事）就是瑣碎，但**還是要有這個 Round 區塊**，只是 Summary 一句話、
Handoff 只留「現況」一句，Status 多半 `DONE`。兩個標題仍然都要有。

具體訊號：

| 訊號 | 不瑣碎（寫詳細） | 瑣碎（一句話帶過） |
|---|---|---|
| 檔案異動 | 有改到／新增／刪除檔案 | 完全沒動任何檔案 |
| 決策 | 做了會影響後續方向的選擇 | 沒有做任何選擇，純粹回應 |
| Status | `IN_PROGRESS` / `BLOCKED`（還有事沒完） | `DONE` 且沒有任何懸而未決 |
| 內容重複性 | 帶來新資訊 | 只是重複或確認前一輪已經記過的事 |

## Round Segments：單輪內的階段性記錄

一輪如果包含好幾個明顯階段（先探索、再做決策、再實作、再驗證），不要全部
憋到最後才寫一次 Summary／Handoff——那樣中途 crash 會整輪的過程全部遺失，事後也
看不出中間走過的路。改成邊做邊在這輪底下追加階段性子區塊，插在 User Input 和
收尾的 Summary／Handoff 之間：

`````markdown
## Round 15 — 2026-09-09T09:00:00+08:00

### User Input
幫我重構 XXX 模組

### 段落 1 - 09:12
讀完現有程式碼，發現三個地方耦合...

### 段落 2 - 09:20
決定拆成 A/B 兩個檔案，理由...

### 段落 3 - 09:35
完成拆分，跑測試全過

### Summary
把 XXX 模組拆成 A/B 兩個檔案，測試全過。

### Handoff
#### 決策
拆成 A/B，理由是三處耦合都集中在同一個檔。
#### 檔案
新增 a.ts、b.ts；刪除 xxx.ts。尚未 commit。
#### 現況
拆分完成，測試全過。

### Status
DONE
`````

這個範例是 DONE 且沒有後續，所以沒有 `#### 下一步` 標題；只有 IN_PROGRESS／BLOCKED 才寫這個小節。

**什麼時候該寫一個段落**：跟判斷 `Status: IN_PROGRESS` 用的同一套標準——「有意義的
階段性結果」，不是照時間或工具呼叫次數機械觸發。短的、沒什麼階段可言的一輪，
照舊只寫 Summary／Handoff 就好，不用硬湊段落。不要把段落內容再抄進 Summary 或 Handoff。

主路徑仍是判斷何時寫段落，不是照時間機械切段。另外有一道保底：`/devlog-tracker:start`
之後，同一輪若連續 10 分鐘（`max_silent_seconds`，預設 600）都沒改 `devlog.md`，
下一個工具會被 PreToolUse hook 擋住。被擋時先 **Read** `.devlog/devlog.md`，再用
Edit／StrReplace **追加**一段 `### 段落`（一行也可以）；**禁止**用 Write 覆寫整份檔。
寫了任何內容計時就歸零。不要用 Bash 繞過。沒呼叫工具就不會響。Claude Code
dynamic workflow／subagent 的 PreToolUse 若帶非空 `agent_id`，此閥門會跳過（它們
與主對話共用 `session_id`，不該被逼寫父輪段落）。門檻用
`/devlog-tracker:segment-watch <時間長度>`（例如 `/devlog-tracker:segment-watch 5 分鐘`）
調整，不用手改 `.devlog/.segment-state` 的 `max_silent_seconds`。

收尾時 Stop hook 仍會要求最後一個 Round 上看得到 `### Summary` 與 `### Handoff`。

## Reply Fold：把「Claude 提問、user 回答」記成同一個 Round

一輪如果是 Claude 用純文字結尾提出一個具體問題（不是用 `AskUserQuestion`
工具、而是整個 turn 就在這句問題上結束），下一則使用者訊息通常就是答案，
不是新話題。預設行為（每個 `UserPromptSubmit` 開一個新 `## Round`）會把這
組問答拆成兩個不相關的 Round。Reply Fold 讓這種情況折進同一個 Round，記
成一個 `### 段落`。

**跟 `AskUserQuestion` 工具的差異：** 用 `AskUserQuestion` 問問題時，問題
跟答案都在同一個 turn 裡（呼叫工具、拿到結果，沒有中間的 Stop），根本不
會產生第二個 Round，不需要也不該用 Reply Fold。Reply Fold 只處理「整個
turn 已經結束、下一則訊息才拿到答案」這種情況。

**什麼時候該開：** 這一輪的 Summary／Handoff／Status 寫完、確定要用文字
問題結束這個 turn（Status 常見是 `BLOCKED`，但 `IN_PROGRESS` 也可能）時，
在結束 turn 之前用 Bash 執行：

```bash
CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/await-open.sh"
```

這會寫入 `.devlog/.awaiting-reply`，記住「下一則訊息大概是在回答這個
Round」。不需要使用者下任何指令，也不用手寫這個 JSON。

**下一則訊息進來之後會自動發生什麼事：** `round-start.sh` 看到
`.awaiting-reply` 且輪次跟目前最後一個 `## Round` 吻合，就不開新 Round，
改成在那個 Round 的 `### Summary` 之前插入一個新段落：

`````markdown
### 段落 2 - 14:32（回覆上一輪的問題）
```text
<使用者這則訊息的原話，跟 User Input 一樣的截斷/遮罩規則>
```
`````

`.devlog/.round-open` 會重新指向這個 Round，讓這輪如果又意外中斷，
`INTERRUPTED` 一樣能正確蓋在同一個 Round 上。折入之後 Claude 照常編輯
這個 Round 的 Summary／Handoff／Status，反映答案後的結果。

**猜錯的處理：** hook 沒辦法驗證「下一則訊息真的是在回答」，只看
`.awaiting-reply` 有沒有開著。如果開了之後使用者其實問了不相干的新問題，
還是會被自動折進舊 Round 當一個段落。發現猜錯時，在那個段落裡說明「其實
是新話題」，然後自己手動開一個新的 `## Round` 接手新請求——不用回頭改寫
被誤折的段落。

**背景 task-notification 也走同一套折疊，但完全自動：** 如果送進來的
`prompt` 本身是一段 `<task-notification>…</task-notification>`（子 agent
在背景完成的通知，不是使用者真的打字），`round-start.sh` 會自己偵測、不
需要 Claude 先跑 `await-open.sh`。原始 XML 不會被記下來，只留一行精簡摘要
（例如 `Agent "Fix wave" finished（status=completed, task-id=t1）`），折成
`### 段落 N - HH:MM（背景任務通知）` 插進最後一個 Round；若當時 `devlog.md`
還沒有任何 Round，才會退回開一個新 Round，但內容一樣是精簡摘要。

這個標記檔也會跨 `/clear` 存活：如果開了之後中間發生過一次 `/clear`，
下一則訊息進來時 Claude 早就不記得當初問的是什麼，卻還是會被折進那個
已經沒有上下文的舊 Round。發現時的處理跟上面猜錯的情況一樣——在那個段落
裡說清楚，再手動開一個新的 `## Round` 接手。

**跟 Span Mode 的關係：** 兩者同時存在時（不常見），Span Mode 優先——這個
tick 會被 Span Mode 安靜跳過，`.awaiting-reply` 照樣被消耗掉但不產生任何
折入。

**跟 checkpoint 計數的關係：** 折入的這個 tick 不算開新 Round，
`rounds_since_checkpoint` 不會遞增，跟 Span Mode 跳過的 tick 待遇一致。

## Span Mode：橫跨多次自動續接的長任務

`/loop` 動態模式、`Workflow`、或任何會讓 Claude 被自己排程（`ScheduleWakeup`、
背景 agent 完成通知）反覆喚醒、而不是被使用者手動打字觸發的長任務，如果每次
自動喚醒都被當成一輪、強制要求完整寫入 devlog.md，會逼出很多沒有意義的紀錄，
或是卡住整個自動化流程。Span Mode 是這種情境下的例外機制。

### 什麼時候該開一個 span

只有在**確定接下來會進入一連串自動續接**時才開（例如剛要開始跑 `/loop` 動態
模式、或剛派出一個 `Workflow`），不是每輪隨便判斷。一般的互動式對話不需要，
也不應該開 span。

### 怎麼開一個 span

寫完這一輪正常的 Round 區塊（Status 用 `IN_PROGRESS`）之後，使用
`/devlog-tracker:span`（或跑 `span-open.sh`）建立 `.devlog/.span-open`。
除非腳本不可用，否則不要手寫 JSON。檔案格式如下：

```json
{
  "round": 12,
  "opened_at": "2026-09-08T21:40:00+08:00",
  "ticks_since_checkin": 0,
  "max_silent_ticks": 5
}
```

- `round`：剛寫的那個 Round 的編號
- `opened_at`：現在的 ISO 8601 時間戳
- `ticks_since_checkin`：固定從 0 開始
- `max_silent_ticks`：這個 span 容許連續幾次自動 tick 都不寫 devlog.md，自己
  依任務性質挑一個合理值（沒有標準答案，抓 5 這類量級即可）

### span 開著的時候會自動發生什麼事

不用手動維護——`round-start.sh` 每次自動續接觸發時會自己把 `ticks_since_checkin`
+1，`enforce-devlog.sh` 只要這個數字還沒到 `max_silent_ticks` 就直接放行，
devlog.md 完全不用動。一旦累積到門檻，Stop hook 會退回正常模式，**這一輪就
會被要求寫東西才能結束**——看到這種擋下來的訊息，代表這個 span 的「安靜額度」
用完了，寫點輕量的進度（不用完整 Round，一行都可以）就能讓它繼續運作。
前提是最後一個 Round 裡已經有 `### Summary` 與 `### Handoff`——一行是追加到那個 Round，不是新開一個缺標題的 Round。若這輪是新開的 Round，兩個標題都要有。

### 怎麼關掉一個 span

整個 Ask 真的做完時：**開一個新的 Round**（不要回頭改寫當初開 span 那個
Round），User Input 可以寫「（自動續接收尾，接續 Round 12）」；Summary 用 2–4 句
給人看這段自動化的結論；Handoff 依四個小節總結整段期間做了什麼（決策／檔案／現況／
下一步）；Status 正常寫 `DONE`／`IN_PROGRESS`／`BLOCKED`；然後刪掉 `.devlog/.span-open`。

### 已知限制：分辨不出「這是自動續接還是真人插話」

Claude Code 目前沒有任何 hook 欄位能分辨一個 tick 是自動排程觸發的，還是使用
者真的手動打了新訊息——這兩種在 span 開著時會被一視同仁地當成一個 tick。如果
span 開著時你發現進來的其實是一個跟自動任務無關的新請求，應該自己先關掉 span
（刪除 `.span-open`、補寫收尾的 Round）再處理新請求，不要讓它悄悄被吞進正在
開著的 span 裡。

### 崩潰時的風險

span 開著時 session 如果崩潰，最壞會漏記最近 `max_silent_ticks` 個 tick 的
活動——不是整段 span，風險有明確上限。這是跟「回合進行到一半被砍斷」（見上面
「需要誠實說明的邊界」）同一類、但用 tick 數量而不是單一回合為界的風險。

## Checkpoint Mode：定期摘要

跟 Span Mode 處理的是不同問題：Span Mode 管的是「一輪內部/自動續接期間要不要
強制寫」，Checkpoint Mode 管的是「累積夠多輪之後，要不要在 devlog.md 裡插入一段
橫跨多輪的摘要」，讓翻閱 devlog.md 的人不用逐輪爬完才知道整體進度。

### 怎麼運作（不用手動開關）

`/devlog-tracker:start` 會自動建立 `.devlog/.checkpoint-state`，之後全程自動：

- 每個互動輪次，`round-start.sh` 把裡面的 `rounds_since_checkpoint` +1
  （Span Mode 的 span 開著、這個 tick 會被安靜放行時不算）
- `enforce-devlog.sh` 每輪檢查一次：如果 `devlog.md` 裡 `## Checkpoint` 開頭的
  標題數量比上次看到的多，代表這輪寫了新的 checkpoint，自動把計數器歸零；
  否則如果 `rounds_since_checkpoint` 已經到 `max_silent_rounds`（預設 20），
  就擋下這一輪，要求補寫一段摘要

### 被要求補寫的時候該怎麼寫

在 `devlog.md` 尾端追加：

```markdown
## Checkpoint（Round <X>-<Y> 摘要）
這段期間完成了...、修了...、決定採用...
```

`X`-`Y` 是這段還沒被摘要過的 Round 範圍，內容對齊各輪 Summary 抓重點就好，不用逐輪複述、
也不要變成各輪 Handoff 的合集——細節本來就還留在 Round 區塊裡，checkpoint 只是給翻閱時的路標，
不替代每輪 Summary。寫完之後這一輪就會正常結束，不用再做任何事。

### 調整門檻

`max_silent_rounds` 預設 20，覺得這個專案的節奏不合適，可以直接編輯
`.devlog/.checkpoint-state` 改掉這個數字，跟 Span Mode 調整 `max_silent_ticks`
是同一套邏輯。

### `/devlog-tracker:pause` 之後

暫停強制記錄時 `.checkpoint-state` 不會被刪除，計數保留；之後重新
`/devlog-tracker:start` 會接著原本的計數繼續，不會歸零重算。

## 壓縮歸檔：`/devlog-tracker:compact`

歸檔不再是自動觸發，而是使用者主動下 `/devlog-tracker:compact` 指令時才做（見 `commands/compact.md`）。
規則：

- 保留：專案摘要（如果有）、最近 5 輪、所有還沒 `DONE`（`IN_PROGRESS`/`BLOCKED`/`INTERRUPTED`）的輪次
- 其餘 `DONE` 的舊輪次：完整搬到 `.devlog/devlog.archive.md`（append，不覆寫既有歸檔）
- 只搬移，不刪除、不改寫內容

## 具名保存：`/devlog-tracker:keep`

掃描整份 `devlog.md`，把值得留名的主題段落一次分別**搬走**成 `.devlog/devlog.<name>.md`（也可只抽出一段，或合併成全部歷史一個檔）。這不是 compact：compact 把舊的 `DONE` 輪次 append 進 `devlog.archive.md`；keep 寫的是一個主題一個檔，且從不寫 archive。步驟見 `commands/keep.md`。不要自動觸發。

## 接續具名保存：`/devlog-tracker:resume <name>`

需要重啟具名主題時，用 resume 讀取 `.devlog/devlog.<name>.md` 的最後一輪與
Handoff；新工作仍記錄到 `devlog.md`，不要改寫 keep 檔。SessionStart 不會自動注入具名檔。

## 無條件清空：`/devlog-tracker:clean`

把 `devlog.md` 整份清空（含專案摘要與所有 Round 歷史），不搬移、不備份，不可復原。跟 compact／keep 不一樣：那兩個都是「搬去別的檔案保留」，clean 是真的丟棄。執行前一定要先問使用者、拿到明確的「清空」才動手；只有目前開著的那一輪會留下，重編成 `## Round 1`。步驟見 `commands/clean.md`。不要自動觸發。

## 跟原版 agentflow 的差異

| | agentflow 原版 | 這個簡化版 |
|---|---|---|
| 涵蓋範圍 | devlog 協定 + 10 步驟 SDD pipeline | 只有 devlog 協定 |
| 接續機制 | `godev` 關鍵字 + stop hook | `/devlog-tracker:start` 開開關；SessionStart 在 startup / resume / compact / fork 注入；`/clear` 後用 `/devlog-tracker:continue` |
| 記錄機制 | 依 SDD 步驟完成度寫入 | 開關開著時 Stop hook 強制每輪都要更新，跟 plan 完成度無關 |
| worker | 內建 subagent 或 external runner 外包 | 沒有，全部由當前 session 直接處理 |
| 審查機制 | 對抗式審查、3ways 多模型辯論 | 沒有 |
| 歸檔觸發 | 依大小自動判斷 | 使用者主動下 `/devlog-tracker:compact`；有主題要留名時用 `/devlog-tracker:keep` |
