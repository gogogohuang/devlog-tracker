---
name: devlog-tracker
description: 在專案根目錄維護一份 devlog.md，把每一輪的請求、所做的決策與結果寫成永久紀錄。使用者下 /devlog-tracker:start 啟動這個專案的強制記錄後，Stop hook 會卡住每一輪的結束動作，逼 Claude 先把這輪寫進 devlog.md 才能結束；SessionStart hook 在 startup / resume / clear / compact 時自動讀檔補齊進度；/devlog-tracker:pause 可暫停強制、/devlog-tracker:compact 可手動壓縮歸檔；長任務有 Span Mode、長對話有 Checkpoint Mode 定期摘要。當使用者提到「devlog」「start」「記錄這輪」，或整個對話呈現需要長期追蹤、跨多個 session 接續的多輪開發工作時，主動使用此技能。
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

第一次使用時，若 `.devlog/` 不存在就建立它。

## 用 `/devlog-tracker:start` 明確開啟強制記錄（不用猜這輪有沒有呼叫到 skill）

Claude Code 目前沒有正式、穩定的方式讓 hook 知道「這一輪有沒有呼叫到某個 skill」，
所以這裡不猜也不解析 transcript，改用一個明確的開關檔案 `.devlog/.enabled`：

- 使用者下 `/devlog-tracker:start`：建立這個開關檔（見 `commands/start.md`），代表「這個專案從現在起
  要強制記錄」，同時讀一次現有 devlog 摘要目前進度
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
意外中斷會把同一塊標成 `INTERRUPTED`（process 被殺時，Status 要等下次 SessionStart 或
下一則訊息才補上）。中間沒寫成 `### 段落` 的過程仍會丟——Segment Watch 只在還有下一個
工具呼叫時催促。

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

## 自動接續（由 hook 負責，不需要使用者喊指令）

這個 plugin 內建一個 SessionStart hook（`hooks/hooks.json` + `hooks/scripts/session-start-devlog.sh`），
matcher 設為 `startup|resume|clear|compact`，也就是**開新 session、resume、使用者按 `/clear`，或 `/compact` 壓縮對話之後**都會自動觸發：

1. 腳本讀取 `.devlog/devlog.md`，只取最近 8 輪（避免整份塞爆 context）
2. 印到 stdout，Claude Code 會把這段文字當成這次 session 的 additionalContext 自動注入
3. Claude 收到這段 context 後，開場就已經知道目前進度，**不用使用者再手動要求接續**

找不到 `.devlog/devlog.md` 時 hook 直接 exit 0，不輸出任何東西，不會干擾沒有用 devlog 的專案。

如果 hook 沒有生效（例如使用者不是用 Claude Code、或 hook 因為某些環境問題沒跑），Claude 仍應主動：
使用者在已有 devlog.md 的專案裡提出一般開發需求時，先讀一次 `.devlog/devlog.md` 最後幾輪再接手，
把 hook 當作「保證會發生」的機制，把 Claude 自己主動讀檔當作 fallback。

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
- `INTERRUPTED` 只由 hook 在意外中斷時寫上（Esc、非 usage 的 API 錯誤、SessionEnd、
  下次 SessionStart / 下一則訊息發現 `.round-open` 還在）。Claude 正常收尾時不要自己選這個值。
  usage 用光（`rate_limit` / `billing_error` / `account_on_hold`）不標中斷。
- 每輪一個區塊，不要把多輪內容合併寫成一個 Round。
- 不要另外開欄位列「這輪用了哪些 skill」——那是稽核用途，跟接續開發沒有直接關係。只有
  當接續動作**必須**重新載入某個特定 skill 才能正確接手時，才把 skill 名稱寫進 Handoff
  「下一步」裡。

Stop hook 會檢查最後一個 Round 是否同時有 `### Summary` 與 `### Handoff` 這兩行標題
（只驗標題存在，不驗寫得好不好）。新開的 Round 兩個標題都要有，瑣碎輪也不例外。

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
之後，同一輪若連續 15 分鐘（`max_silent_seconds`，預設 900）都沒改 `devlog.md`，
下一個工具會被 PreToolUse hook 擋住，要求先追加一段 `### 段落`（一行也可以）。
寫了任何內容計時就歸零。被擋時用 Write／Edit 改 `.devlog/devlog.md`，不要用 Bash
繞過。沒呼叫工具就不會響。門檻可直接改 `.devlog/.segment-state` 的
`max_silent_seconds`。

收尾時 Stop hook 仍會要求最後一個 Round 上看得到 `### Summary` 與 `### Handoff`。

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

寫完這一輪正常的 Round 區塊（Status 用 `IN_PROGRESS`）之後，額外用 Write／Edit
工具建立 `.devlog/.span-open`：

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

- 保留：專案摘要（如果有）、最近 5 輪、所有還沒 `DONE`（`IN_PROGRESS`/`BLOCKED`）的輪次
- 其餘 `DONE` 的舊輪次：完整搬到 `.devlog/devlog.archive.md`（append，不覆寫既有歸檔）
- 只搬移，不刪除、不改寫內容

## 跟原版 agentflow 的差異

| | agentflow 原版 | 這個簡化版 |
|---|---|---|
| 涵蓋範圍 | devlog 協定 + 10 步驟 SDD pipeline | 只有 devlog 協定 |
| 接續機制 | `godev` 關鍵字 + stop hook | `/devlog-tracker:start` 指令建立開關檔 + Stop/SessionStart hook |
| 記錄機制 | 依 SDD 步驟完成度寫入 | 開關開著時 Stop hook 強制每輪都要更新，跟 plan 完成度無關 |
| worker | 內建 subagent 或 external runner 外包 | 沒有，全部由當前 session 直接處理 |
| 審查機制 | 對抗式審查、3ways 多模型辯論 | 沒有 |
| 歸檔觸發 | 依大小自動判斷 | 使用者主動下 `/devlog-tracker:compact` |
