# Span Mode：橫跨多次自動續接的長任務

`/loop` 動態模式、`Workflow`、或任何會讓 Claude 被自己排程（`ScheduleWakeup`、
背景 agent 完成通知）反覆喚醒、而不是被使用者手動打字觸發的長任務，如果每次
自動喚醒都被當成一輪、強制要求完整寫入 devlog.md，會逼出很多沒有意義的紀錄，
或是卡住整個自動化流程。Span Mode 是這種情境下的例外機制。

設計動機、hook 機制細節見 `docs/design/span-mode.md`；這裡只講操作規則。

## 什麼時候該開一個 span

只有在**確定接下來會進入一連串自動續接**時才開（例如剛要開始跑 `/loop` 動態
模式、或剛派出一個 `Workflow`），不是每輪隨便判斷。一般的互動式對話不需要，
也不應該開 span。

## 怎麼開一個 span

寫完這一輪正常的 Round 區塊（Status 用 `IN_PROGRESS`）之後，使用
`/devlog-tracker:span`（或跑 `DEVLOG_PLATFORM="<你所在的平台：claude／codex／cursor>" DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd)>" bash "${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/core/scripts/span-open.sh"`）建立你所在平台的 span 檔（Claude Code 是 `.devlog/.span-open`，Codex／Cursor 是 `.devlog/.span-open@codex`／`.devlog/.span-open@cursor`）。
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

## span 開著的時候會自動發生什麼事

不用手動維護——`round-start.sh` 每次自動續接觸發時會自己把 `ticks_since_checkin`
+1，`enforce-devlog.sh` 只要這個數字還沒到 `max_silent_ticks` 就直接放行，
devlog.md 完全不用動。一旦累積到門檻，Stop hook 會退回正常模式，**這一輪就
會被要求寫東西才能結束**——看到這種擋下來的訊息，代表這個 span 的「安靜額度」
用完了，寫點輕量的進度（不用完整 Round，一行都可以）就能讓它繼續運作。
前提是最後一個 Round 裡已經有 `### Summary`、`### Reply` 與 `### Handoff`——一行是追加到那個 Round，不是新開一個缺標題的 Round。若這輪是新開的 Round，三個標題都要有。

## 怎麼關掉一個 span

整個 Ask 真的做完時：**開一個新的 Round**（不要回頭改寫當初開 span 那個
Round），User Input 可以寫「（自動續接收尾，接續 Round 12）」，其餘照 SKILL.md
「每一輪的紀錄格式」完整收尾（Summary／Reply／Handoff／Status，Handoff 小節的
必寫與省略規則相同），內容總結整段 span 做了什麼；然後跑
`DEVLOG_PLATFORM="<你所在的平台：claude／codex／cursor>" DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd)>" bash "${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT}}/core/scripts/span-close.sh"`
關掉 span（不要手動刪 span 檔）。

span 裡自己新開的 Round 編號照 SKILL.md 的規則取（最後一個 `## Round <N>` 加 1）。
這種 Round 沒有經過 hook 預留編號，所以併回 devlog.md 時如果編號已經被佔用
（devlog.md 已有、或另一個平台開著的輪次預留了它），hook 會自動改成下一個
空號——之後引用這個 Round 時以 devlog.md 裡的編號為準。

## 已知限制：分辨不出「這是自動續接還是真人插話」

Claude Code 目前沒有任何 hook 欄位能分辨一個 tick 是自動排程觸發的，還是使用
者真的手動打了新訊息——這兩種在 span 開著時會被一視同仁地當成一個 tick。如果
span 開著時你發現進來的其實是一個跟自動任務無關的新請求，應該自己先關掉 span
（跑上面那行 `span-close.sh`、補寫收尾的 Round）再處理新請求，不要讓它悄悄被吞進正在
開著的 span 裡。

## 崩潰時的風險

span 開著時 session 如果崩潰，最壞會漏記最近 `max_silent_ticks` 個 tick 的
活動——不是整段 span，風險有明確上限。這是跟「回合進行到一半被砍斷」（見
SKILL.md「需要誠實說明的邊界」）同一類、但用 tick 數量而不是單一回合為界的風險。
