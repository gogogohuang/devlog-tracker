# devlog-tracker

在專案中維護一份 `.devlog/devlog.md`，把每一輪對話的請求、決策與結果寫成永久紀錄。
參考 [agfnow/agentflow](https://github.com/agfnow/agentflow) 的 devlog 基礎協定做的簡化版，
只保留「逐輪對話紀錄」這一層。

## 特色

- **`/devlog-tracker:start` 明確開啟強制記錄**：建立 `.devlog/.enabled` 開關檔，之後 `Stop` hook 會卡住
  每一輪的結束動作，這一輪沒寫 `devlog.md` 就不能結束——不依賴 Claude 自行判斷「值不值得
  記錄」，也跟任務/plan 是否完成無關。沒下過 `/devlog-tracker:start` 的專案完全不受影響。
  `UserPromptSubmit` 在每一則使用者訊息送出時就先寫好 User Input skeleton；意外中斷
  （非 usage 的 API 錯誤、SessionEnd、殘留的 `.round-open`）會把同一塊標成
  `INTERRUPTED`（usage 用光不算中斷）。中途取消（例如 Esc）通常是在**下一則訊息**或
  **下次 SessionStart（startup / resume / clear / fork）**才補上；`PostToolUseFailure` 的
  `is_interrupt` 若有觸發，只是 best-effort 的額外路徑，不能當成一定會立刻蓋章。
- **`/devlog-tracker:pause`**：暫停強制記錄，歷史紀錄不受影響，之後可再用 `/devlog-tracker:start` 重新啟動。
- **自動接續**：`SessionStart` hook，`/clear`、resume、開新 session、`/fork` 時自動讀取
  `.devlog/devlog.md` 最後幾輪並注入 context，不用手動喊指令。
- **`/devlog-tracker:compact`**：手動把已完成的舊輪次搬到 `devlog.archive.md`，避免主檔案無限膨脹。
- **`/devlog-tracker:keep`**：若這段紀錄值得單獨留名，確認後把一段（或全部歷史）從 `devlog.md` 搬走成 `.devlog/devlog.<name>.md`。Claude 會依內容建議範圍與檔名，也可自訂。不是 compact（compact 仍是把舊的 `DONE` 輪次 append 進 `devlog.archive.md`）。細節見 [`docs/design/keep.md`](docs/design/keep.md)。
- **格式固定**：每輪都是 `User Input`（貼近原話，保留彈性）/ `Summary`（人讀結論）/ `Handoff`（下一輪接續：決策、檔案、現況、下一步）/ `Status`（只寫 `DONE` / `IN_PROGRESS` / `BLOCKED` / `INTERRUPTED`），讀檔案就能還原對話重點，不用翻對話紀錄。細節見 [`docs/design/summary-handoff.md`](docs/design/summary-handoff.md) 和 SKILL.md。
- **Span Mode（進階功能）**：`/loop` 動態模式、`Workflow` 這類會被自動排程反覆喚醒的長任務，不用每個自動 tick 都寫一次 devlog——用 tick 計數安全閥（`max_silent_ticks`）保底，崩潰最多漏記固定數量的 tick，不是整段。細節見 [`docs/design/span-mode.md`](docs/design/span-mode.md)。
- **段落記錄 + Checkpoint Mode（進階功能）**：單輪內有多個階段性結果時，邊做邊寫成 `### 段落` 子區塊而不是憋到最後；同一輪若連續約 15 分鐘沒改 `devlog.md`，`PreToolUse` hook 會擋住下一個工具要求先補一段（門檻可調）。累積輪數夠多時，`Stop` hook 會提醒補上一段跨輪的 `## Checkpoint` 摘要（門檻預設 20 輪、可調）。已經啟用過強制記錄的專案要再跑一次 `/devlog-tracker:start` 才會建立 `.segment-state`。細節見 [`docs/design/checkpoint-mode.md`](docs/design/checkpoint-mode.md)、[`docs/design/segment-watch.md`](docs/design/segment-watch.md) 和 SKILL.md。

## 安裝

作為 Claude Code plugin 安裝（會自動更新）：

```
/plugin marketplace add gogogohuang/devlog-tracker
/plugin install devlog-tracker@devlog-tracker
```

## 使用

在專案裡下一次：

```
/devlog-tracker:start
```

之後正常跟 Claude 對話即可，每一輪結束前都會被強制檢查、補上 `.devlog/devlog.md` 的紀錄。

暫停強制記錄：

```
/devlog-tracker:pause
```

累積輪數變多、檔案太長時：

```
/devlog-tracker:compact
```

這段開發紀錄值得單獨留名時：

```
/devlog-tracker:keep
```

（以上都是完整的 namespace 形式，plugin 名稱是 `devlog-tracker`。）

## 目錄結構

```
devlog-tracker/
├── .gitignore
├── .claude-plugin/
│   ├── plugin.json        # plugin manifest
│   └── marketplace.json   # 讓這個 repo 本身就是一個 marketplace
├── docs/design/
│   ├── span-mode.md           # Span Mode 設計文件
│   ├── checkpoint-mode.md     # Checkpoint Mode 設計文件
│   ├── segment-watch.md       # 單輪沉默 15 分鐘保底
│   ├── summary-handoff.md     # 每輪 Summary（人）+ Handoff（AI）設計文件
│   ├── recording-moments.md   # 送出時 skeleton、正常收尾、意外 INTERRUPTED
│   └── keep.md                # 具名搬走成 devlog.<name>.md
├── skills/devlog-tracker/SKILL.md
├── hooks/
│   ├── hooks.json                       # SessionStart / UserPromptSubmit / PreToolUse / Stop / StopFailure / SessionEnd / PostToolUseFailure
│   └── scripts/
│       ├── session-start-devlog.sh      # 自動接續（含 Span Mode 恢復提醒、殘留 .round-open 補 INTERRUPTED）
│       ├── round-start.sh               # 送出時寫 Round skeleton、拍雜湊，遞增 Span/Checkpoint 計數，重設 Segment Watch 計時
│       ├── close-open-round.sh          # 把開著的 Round 標成 INTERRUPTED（共用 helper）
│       ├── on-stop-failure.sh           # StopFailure：非 usage 錯誤標中斷
│       ├── on-session-end.sh            # SessionEnd：殘留 round 標中斷
│       ├── on-tool-failure.sh           # PostToolUseFailure：工具失敗時標中斷
│       ├── segment-watch.sh             # 同一輪太久沒寫 devlog 就擋住下一個工具
│       ├── enforce-devlog.sh            # 強制每輪結束前要寫 Summary/Handoff（含 Span Mode、Checkpoint Mode 檢查）
│       ├── test-close-open-round.sh     # close-open-round 自我檢查
│       ├── test-round-start.sh          # round-start skeleton / heal 自我檢查
│       ├── test-on-interrupt.sh         # StopFailure / SessionEnd / PostToolUseFailure 自我檢查
│       ├── test-enforce-devlog.sh       # enforce + round-start 自我檢查
│       ├── test-segment-watch.sh        # segment-watch + round-start 計時自我檢查
│       └── test-session-start-devlog.sh # session-start-devlog.sh 的自我檢查
└── commands/
    ├── start.md            # 開啟強制記錄（建立 .enabled、.checkpoint-state、.segment-state）
    ├── pause.md            # 暫停強制記錄
    ├── compact.md          # 壓縮歸檔（保留 Checkpoint 區塊，不搬進 archive）
    └── keep.md             # 具名搬走（確認後寫 devlog.<name>.md，再從主檔刪）
```

## License

Apache-2.0
