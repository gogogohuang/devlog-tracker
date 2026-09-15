# Reply Fold：把「Claude 提問、user 回答」記成同一個 Round

一輪如果是 Claude 用純文字結尾提出一個具體問題（不是用 `AskUserQuestion`
工具、而是整個 turn 就在這句問題上結束），下一則使用者訊息通常就是答案，
不是新話題。預設行為（每個 `UserPromptSubmit` 開一個新 `## Round`）會把這
組問答拆成兩個不相關的 Round。Reply Fold 讓這種情況折進同一個 Round，記
成一個 `### 段落`。

## AskUserQuestion（同輪內紀錄，不用 fold）

用 `AskUserQuestion` 問問題時，問題跟答案都在**同一個 turn**裡（呼叫工具、
拿到結果，沒有中間的 Stop），不會產生第二個 Round，**不要**開
`.awaiting-reply`／`await-open.sh`。

但 L1 接手仍要能在檔裡看到「問了什麼、答了什麼」：

1. 呼叫 `AskUserQuestion` **之前或同時**，用 Edit 在 `### Summary` 之前追加：

   `````markdown
   ### 段落 N - HH:MM（AskUserQuestion）
   ```text
   <問題原文／選項摘要>
   ```
   `````

2. 工具回傳答案後，在同一 Round 再追加一段（或併進同一段落）寫清楚使用者選了／回了什麼。
3. 若整輪因此變成在等外部輸入才繼續，收尾 `Status: BLOCKED`，並在 `現況`／`下一步`
   寫缺件句式（缺什麼、出現長怎樣）。

這樣不靠 transcript，下一任只讀 `devlog.md` 就知道澄清題問到哪。

**什麼時候該開 Reply Fold（純文字提問跨 turn）：** 確定要用文字問題結束這個 turn 時，在結束 turn 之前：

1. 先用 Edit 在這個 Round 的 `### Summary` 之前插入一個小段落，記下**這次
   問的問題原文**（跟自動折入答案用同一種格式，方便前後對照）：

   `````markdown
   ### 段落 N - HH:MM（Claude 提問）
   ```text
   <問題原文；hook 已寫的 User Input 規則：送出原文優先，截斷／遮罩見 recording-moments>
   ```
   `````

   這一步不能省——沒有它，devlog 裡只留得下使用者的回答（下一則訊息自動
   折入的段落），問的是什麼反而不見了，事後只看檔案會看不懂答案在答什麼。
2. 確保這一輪的 Summary／Reply／Handoff／Status 存在且有效（`Status` 常見是
   `BLOCKED`，但 `IN_PROGRESS` 也可能）——**第一次**提問要完整寫；如果這已
   經是同一個 Round 內連續第二題以後的提問，且工作區、決策都還沒變，不用
   整段重寫，見下面「連續多輪一問一答」。
3. 用 Bash 執行：

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
<使用者這則訊息的原話；hook 截斷／遮罩規則同 User Input>
```
`````

`.devlog/.round-open` 會重新指向這個 Round，讓這輪如果又意外中斷，
`INTERRUPTED` 一樣能正確蓋在同一個 Round 上。折入之後，如果問答到此結束、
要往下做別的事了，Claude 照常編輯這個 Round 的 Summary／Reply／Handoff／Status，
反映答案後的結果；如果答案帶出**下一個**問題（連續問答），見下面這段。

**連續多輪一問一答（例如 grilling）：只在真正結束時完整收尾。** 一個 Round
裡如果連續好幾輪都是「Claude 問一題、使用者答一題」，不要每題都重寫一次
完整的 Summary／Reply／Handoff／Status——那樣每題都要跑一次大改動，會把使用者剛
答完的內容跟 Claude 剛問的下一題擠開，變得很難照順序讀。改成：

- 答案：下一則訊息進來時，Reply Fold 自動折入，不用手動處理。
- 下一題：只做上面「什麼時候該開」的步驟 1（插入一個 `### 段落
  （Claude 提問）` 記下問題原文）+ 步驟 3（`await-open.sh`），**不必**重寫
  Summary／Reply／Handoff／Status——只要工作區、決策這些沒變，原本那份還有效。
- 真正收尾（結束這整場問答、要換話題或往下做別的事）時，才完整改寫一次
  Summary（總結整場問答得出的結論）、Reply（對使用者說過的結論／未決提問）與
  Handoff（決策／現況／完成條件／下一步，反映最終結果），Status 改成當下該有的值。

這樣一整場問答結束後，devlog 裡會依序留下每一題的原文段落與對應的回答
段落，跟一份收尾時寫的總結——問題和答案都保留了，但中途不會被大段落
的收尾內容打斷。

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
