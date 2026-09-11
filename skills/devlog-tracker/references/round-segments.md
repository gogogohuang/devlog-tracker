# Round Segments：單輪內的階段性記錄

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

這個範例是 DONE 且沒有後續，所以沒有 `#### 工作區` 與 `#### 下一步`；這兩節只有 IN_PROGRESS／BLOCKED 才寫。

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
