# devlog-tracker

**版本** 0.8.0

在專案中維護一份 `.devlog/devlog.md`，把每一輪對話的請求、決策與結果寫成永久紀錄。對話一 `/clear` 或換 session 就沒了；這份檔案取代那個缺口，讓工作可以中斷再接。沒下過 `/devlog-tracker:start` 時，裝著也不會動任何檔案。

## 這是什麼

把「這輪做了什麼、決定了什麼、下一步是什麼」寫進專案內的 `devlog.md`。Stop hook 保證每輪都寫完才放行；沒明確 `/devlog-tracker:start` 前不會建立或改動 `.devlog/`。

## 安裝

作為 Claude Code plugin 安裝（會自動更新）：

```
/plugin marketplace add gogogohuang/devlog-tracker
/plugin install devlog-tracker@devlog-tracker
```

### Cursor（選用）

Claude Code 仍是主要安裝方式。若要在 Cursor workspace 使用，先設定
`DEVLOG_TRACKER_ROOT` 為本 plugin 的絕對路徑，再把 `cursor/hooks.json` 的
`hooks` 合併進專案 `.cursor/hooks.json`。也可以把整個 `cursor/hooks/` 與
`hooks/scripts/` vendoring 到專案，並調整 command 路徑；兩者的相對目錄必須維持可用。

Cursor cloud agent 不執行 `sessionStart`，因此不會自動注入接手摘要；其他已設定的
hook 仍依 Cursor 支援的事件執行。

Cursor 沒有 `/devlog-tracker:*` slash 指令面；hooks 裝好後，請用與 Claude commands
相同的腳本（`commands/*.md` 會優先讀 `CLAUDE_PLUGIN_ROOT`，否則讀
`DEVLOG_TRACKER_ROOT`）：

```bash
export DEVLOG_TRACKER_ROOT=/absolute/path/to/devlog-tracker
export CLAUDE_PROJECT_DIR="$(pwd)"
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/start-devlog.sh"
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/status-devlog.sh"
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/segment-watch-set.sh" 600
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/checkpoint-set.sh" 20
# pause / span-open / span-close / compact / keep-move / clean / resume：見 commands/*.md
```

## 快速開始

在專案裡下一次：

```
/devlog-tracker:start
```

之後正常跟 Claude 對話即可，每一輪結束前都會被強制檢查、補上 `.devlog/devlog.md` 的紀錄。`/clear` 之後 context 是空的；要接著做上一題，下 `/devlog-tracker:continue`。暫停、歸檔、具名搬走、狀態與 span 見下方指令表（完整 namespace，plugin 名稱是 `devlog-tracker`）。

## 指令

| 指令 | 做什麼 |
|---|---|
| `/devlog-tracker:start` | 跑腳本建立 `.devlog/.enabled`（缺的 state 檔會補上，已有門檻不重置）。讀檔對進度，不自動開工。`.devlog/` 含 prompt，會建議加進 `.gitignore`，要你同意才改。 |
| `/devlog-tracker:continue` | 讀 `.devlog/devlog.md`，依最後一輪 Handoff 的下一步接著做。`/clear` 之後要接續用這個。細節見 [`docs/design/continue.md`](docs/design/continue.md)。 |
| `/devlog-tracker:pause` | 暫停強制記錄，歷史檔不動，之後可再 `start`。 |
| `/devlog-tracker:compact` | 腳本把較舊的 `DONE` 輪次搬到 `devlog.archive.md`（Checkpoint 與未完成輪留在主檔）。 |
| `/devlog-tracker:keep` | 掃全檔分主題，一次列出建議，確認後把各段各自搬走成 `devlog.<name>.md`；也可抽出一段或合併成全部歷史一檔。不是 compact。細節見 [`docs/design/keep.md`](docs/design/keep.md)。 |
| `/devlog-tracker:resume <name>` | 讀具名保存檔的最後一輪與 Handoff，新工作仍寫回主 `devlog.md`。 |
| `/devlog-tracker:clean` | 無條件清空 `devlog.md`（含專案摘要與所有 Round 歷史），不搬移、不備份、不可復原；執行前一定會先問，要明確回覆「清空」才動手。只留目前開著的那一輪，重編成 `## Round 1`。 |
| `/devlog-tracker:status` | 查看強制記錄開關、Span、Checkpoint、Segment Watch 與最後一輪 Status。 |
| `/devlog-tracker:span` | 開啟或關閉自動續接長任務使用的 Span Mode（不要手寫 `.span-open` JSON）。 |
| `/devlog-tracker:segment-watch <時間長度>` | 調整 Segment Watch 的沉默門檻（預設 10 分鐘）。專案還沒 `/devlog-tracker:start` 時回報 `NOT_STARTED`，不會建立任何檔案。 |
| `/devlog-tracker:checkpoint <輪數>` | 調整 Checkpoint Mode 的沉默門檻（預設 20 輪）。專案還沒 start 時回報 `NOT_STARTED`。 |

## 強制記錄開著之後

```mermaid
sequenceDiagram
  participant U as 使用者
  participant H as Hooks
  participant C as Claude
  participant D as .devlog/devlog.md

  U->>H: 送出訊息
  H->>D: 先寫 Round skeleton（User Input + IN_PROGRESS）
  C->>D: 補 Summary / Handoff，改 Status
  C->>H: 這一輪要結束
  alt 沒寫完、標題是空的，或 Status 不合法
    H-->>C: 擋住，要求補寫
  else 寫完了
    H-->>C: 放行
  end
```

每一輪固定四塊：`User Input`（貼近原話，常見 token 會遮罩）、`Summary`（給人掃）、`Handoff`（給下一輪 Claude：決策／檔案／現況／下一步）、`Status`（`DONE` / `IN_PROGRESS` / `BLOCKED` / `INTERRUPTED`）。Stop 會確認標題底下有內容、Status 是這四個值之一，以及進行中／卡住時有「下一步」。細節見 [`docs/design/summary-handoff.md`](docs/design/summary-handoff.md) 和 SKILL.md。

## Hook 會自動做的事

- **自動接續**：`SessionStart` hook 在開新 session、resume、`/compact`、`/fork` 時，注入最後一個 Checkpoint（若有）加上最近兩輪的 Summary / Handoff / Status，不是整份檔。`/clear` 是真的清空，不注入；要接續請 `/devlog-tracker:continue`。細節見 [`docs/design/continue.md`](docs/design/continue.md)。
- **意外中斷**：非 usage 的 API 錯誤、SessionEnd、殘留的 `.round-open` 會把開著的 Round 標成 `INTERRUPTED`。usage 用光不算中斷。中途取消（例如 Esc）通常是在**下一則訊息**或**下次 SessionStart（startup / resume / clear / fork）**才補上；`PostToolUseFailure` 的 `is_interrupt` 若有觸發，只是 best-effort，不能當成一定會立刻蓋章。細節見 [`docs/design/recording-moments.md`](docs/design/recording-moments.md)。
- **段落記錄**：長輪不要憋到最後，邊做邊寫 `### 段落`。同一輪連續約 10 分鐘沒改 `devlog.md`，`PreToolUse` hook 會擋住下一個工具；先 Read 再 Edit／StrReplace 追加一段（不要 Write 覆寫整檔）。門檻可用 `/devlog-tracker:segment-watch <時間長度>` 調整。Claude Code subagent／dynamic workflow（PreToolUse 帶 `agent_id`）不套用父輪這道閥。細節見 [`docs/design/segment-watch.md`](docs/design/segment-watch.md)。
- **Checkpoint Mode**：累積約 20 輪沒寫跨輪摘要，`Stop` hook 會要求補一段 `## Checkpoint`（門檻可調）。細節見 [`docs/design/checkpoint-mode.md`](docs/design/checkpoint-mode.md)。
- **Span Mode**：`/loop`、Workflow 這類自動續接的長任務，不必每個 tick 都寫完整 Round，用 tick 計數當安全閥；崩潰最多漏記固定數量的 tick，不是整段。細節見 [`docs/design/span-mode.md`](docs/design/span-mode.md)。
- **Reply Fold**：Claude 用純文字結尾提出問題、下一則訊息才拿到答案時，不用開新 Round——先跑 `await-open.sh` 標記，下一則訊息就會自動折進同一個 Round 當一段 `### 段落`，不是拆成兩個不相關的 Round。跟 `AskUserQuestion` 工具無關（同一 turn 內問答，本來就不會產生第二個 Round）。背景 task-notification（子 agent 完成通知）也會自動走同一套折疊機制，不留原始 XML，只記精簡摘要。細節見 [`docs/design/reply-fold.md`](docs/design/reply-fold.md)。

## 測試

```
bash hooks/scripts/run-tests.sh
```

含 Cursor adapter。

## License

Apache-2.0
