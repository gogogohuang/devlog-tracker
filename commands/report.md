---
description: 查看 devlog 統計：Round 數、各 Status、BLOCKED 比例、Checkpoint／keep／lessons 數量與時間範圍（純讀取）。
---

這是純讀取，不改任何檔。先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="<專案根目錄絕對路徑，不要用 $(pwd) 重新推>" bash "${PLUGIN_ROOT}/core/scripts/report-devlog.sh"
```

使用者要看所有 branch 的合計時加 `--all-branches`。

- `NOT_STARTED`：告知還沒 `/devlog-tracker:start`，結束。
- 其他輸出是 `KEY=VALUE`，翻成幾行給人看：
  - `BRANCH`：統計的是哪個 branch 的檔案（`--all-branches` 時仍印目前 branch）。
  - `ROUNDS_TOTAL`／`ROUNDS_MAIN`／`ROUNDS_ARCHIVE`：Round 總數與主檔、archive 各自的數量。
  - `STATUS_*`：各 Status 的 Round 數；`BLOCKED_RATIO` 是 BLOCKED 佔總數的百分比（整數）。
  - `CHECKPOINTS`、`KEPT_TOPICS`、`LESSONS_TOPICS`：Checkpoint 區塊、已 keep 主題、Lessons 主題數。
  - `LESSONS_ADVISORY`（有才印）：Lessons Mode 機制性訊號累積次數／門檻。
  - `FIRST_ROUND_AT`／`LAST_ROUND_AT`：第一輪與最後一輪的時間；`none` 表示沒有 Round。

需要機器可讀的輸出（CI、儀表板）時，告訴使用者可以用 `npx devlog-tracker report --json`。
