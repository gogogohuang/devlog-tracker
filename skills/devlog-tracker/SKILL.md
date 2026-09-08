---
name: devlog-tracker
description: 在專案根目錄維護一份 devlog.md，把每一輪的請求、所做的決策與結果寫成永久紀錄。使用者下 /devlog-tracker:start 啟動這個專案的強制記錄後，Stop hook 會卡住每一輪的結束動作，逼 Claude 先把這輪寫進 devlog.md 才能結束；SessionStart hook 在 startup / resume / clear / compact 時自動讀檔補齊進度；/devlog-tracker:pause 可暫停強制、/devlog-tracker:compact 可手動壓縮歸檔。當使用者提到「devlog」「start」「記錄這輪」，或整個對話呈現需要長期追蹤、跨多個 session 接續的多輪開發工作時，主動使用此技能。
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
   先檢查開關檔存在，才記下這一輪開始時 `.devlog/devlog.md` 的內容雜湊到 `.devlog/.turn-start`
2. Claude 想結束這輪回應時，`Stop` hook（`hooks/scripts/enforce-devlog.sh`）
   一樣先檢查開關檔，開著的話才去比對 `.devlog/devlog.md` 現在的內容雜湊跟這一輪開始時是否不同
3. 沒有的話，hook 用 exit code 2 擋下來，把「請補上這輪的 Round 區塊」的訊息回給 Claude，
   Claude 必須先照下面的格式寫完，才能真正結束這輪

好處：就算工作做到一半被中斷（下一輪還沒開始就被使用者關掉、或換 session），
只要**上一輪有正常結束過**，devlog.md 就一定留有當時的 Status（多半是 `IN_PROGRESS`
或 `BLOCKED`）可以接續——這跟「plan 是否完成」完全無關，純粹綁在「這一輪有沒有結束」
這個事件上。

需要誠實說明的邊界：這個機制保證的是「**每個正常結束的回合**」都會被記錄，如果是回合
「進行到一半」就被強制砍掉 session（例如中途斷線、強制終止進程），那一次 Stop hook
根本沒機會執行，那個瞬間的細節不會被補進 devlog——這種情況下能接續到的，是上一個有
正常結束的回合留下的狀態，不會是砍斷當下那一瞬間。如果需要連這種情況都要能還原到
最後一步操作，可以再加一個 `PostToolUse` hook，每次工具呼叫後都寫一行輕量的進度紀錄。

### 兩個穩健性設計（參考 agfnow/agentflow 的 stop-hook.js）

- **loop guard**：`enforce-devlog.sh` 一開始會讀 stdin 的 `stop_hook_active` 欄位——這是
  Claude Code 官方標準欄位，代表「這輪已經被本支 hook 擋下來一次、Claude 正在重跑」，
  此時直接放行，不會一直卡住同一輪。Claude Code 本身也有連續擋 8 次的上限保護，這是多
  一層保險。
- **fail-open**：三支 hook 腳本都不用 `set -e`，每一步可能失敗的地方（讀不到檔案、雜湊
  算不出來）都明確接住、失敗就直接放行。這些腳本的職責是「檢查」，不該因為自己的臭蟲
  就意外把使用者的 session 卡死。

沒有做的一件事：agentflow 的 Stop hook 還會依「這一輪是不是還在進行中」放寬檢查強度——
只有結構性問題才擋，其餘失敗只當警告。這個設計在他們的架構下有意義，是因為他們用
Ask/Reply 配對代表一個可能橫跨多次 Claude 動作才會結束的完整輪次；我們的架構是
Claude Code 原生的「一個使用者訊息 = 一輪」，Stop 本來就只在這一輪真的要結束時才觸發，
沒有「輪次進行中」這個中間狀態要放寬，所以這個設計沒有直接對應的地方可以搬過來。

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

完成一輪工作後（或使用者要求先記錄時），在檔案尾端新增：

```markdown
## Round <N> — <ISO 8601 時間戳，含時區>

### User Input
<使用者這輪的輸入，貼近原話，保留關鍵細節，不用強制逐字照抄>

### Response
<這輪做了什麼、做出的關鍵決策與理由、產出或修改了哪些檔案、有沒有 commit>

### Status
DONE | IN_PROGRESS | BLOCKED
<若是 IN_PROGRESS 或 BLOCKED，補一句「接下來要做什麼」，方便下次接續；
如果接續動作需要依賴某個特定 skill 的流程／步驟才能正確接手（例如還在走某個多步驟
workflow skill 的一半），在這句裡點名那個 skill，讓下一輪的 Claude 知道要重新載入哪個
skill 才接得上——不是每個 skill 都要記，只記「接續必須知道」的那個>
```

Round 編號：讀取檔案中最後一個 `## Round <N>`，本輪用 N+1；檔案不存在就從 Round 1 開始。

寫入原則：
- **User Input 預設貼近使用者原話，但保留彈性，不強制逐字照錄。** 目標是讓人「只讀這份
  檔案、不用翻對話紀錄」就能接續開發，所以要保留原始措辭裡的關鍵細節（用詞、並列條件、
  隨口補充的例外情況），但不用機械式地一字不漏照抄——內容太長、太雜（例如夾雜大段貼上的
  log 或程式碼）時，可以留原文最相關的部分、把明顯的雜訊留在原處摘要帶過，怎麼拿捏由
  Claude 自己判斷，不用每次都整段複製。
- Response 只寫實際發生的事，不要寫「將會」「打算」這種未來式。
- 每輪一個區塊，不要把多輪內容合併寫成一個 Round。
- 不要另外開欄位列「這輪用了哪些 skill」——那是稽核用途，跟接續開發沒有直接關係。只有
  當接續動作**必須**重新載入某個特定 skill 才能正確接手時，才把 skill 名稱寫進 Status
  的「接下來要做什麼」那句話裡（見上面格式範例）。

### 怎麼判斷這輪該寫多細（瑣碎程度）

「每輪都要記錄」管的是**要不要留下這一輪的痕跡**，瑣碎程度管的是**該寫多細**，這是兩件
不同的事——瑣碎不代表可以跳過不記，只代表這輪該寫得短。

判斷測試：**如果把這一輪從 devlog 刪掉，之後光讀檔案接續工作，會不會漏掉重要資訊？**
會漏掉就不瑣碎，要完整寫；不會漏掉（純確認、閒聊、使用者只回「好」「謝謝」、沒有產生任何
實質變化或懸而未決的事）就是瑣碎，但**還是要有這個 Round 區塊**，只是 `Response` 用一句話
帶過，不用展開湊篇幅。

具體訊號：

| 訊號 | 不瑣碎（寫詳細） | 瑣碎（一句話帶過） |
|---|---|---|
| 檔案異動 | 有改到／新增／刪除檔案 | 完全沒動任何檔案 |
| 決策 | 做了會影響後續方向的選擇 | 沒有做任何選擇，純粹回應 |
| Status | `IN_PROGRESS` / `BLOCKED`（還有事沒完） | `DONE` 且沒有任何懸而未決 |
| 內容重複性 | 帶來新資訊 | 只是重複或確認前一輪已經記過的事 |

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
