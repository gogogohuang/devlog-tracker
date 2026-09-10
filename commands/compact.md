---
description: 把 .devlog/devlog.md 裡已完成且較舊的紀錄搬到 devlog.archive.md，避免主檔案無限膨脹
---

請執行 devlog 壓縮：

1. 讀取 `.devlog/devlog.md` 全文。若檔案不存在，告知使用者目前沒有東西可壓縮，不要建立空檔案，結束。
2. 找出所有 `## Round <N>` 區塊，判斷各自的 Status。
3. 保留規則（以下皆保留在 devlog.md，不搬動）：
   - 檔案開頭的專案摘要（如果有）
   - 最近 5 輪（不論 Status 是什麼）
   - 所有 Status 為 `IN_PROGRESS`、`BLOCKED` 或 `INTERRUPTED` 的輪次，不論多舊
   - 所有 `## Checkpoint` 區塊，永遠留在 devlog.md、不搬到 archive——它們是
     checkpoint 機制存在的目的：翻閱時的摘要路標，搬走就失去了作用
4. 跑（不要自己搬檔）：
   先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：
   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
   CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/compact-devlog.sh"
   ```
   檔案不存在時腳本 exit 1：告知沒有東西可壓縮。
5. 用 stdout 的 `MOVED` / `REMAINING` / `ARCHIVE` 回報一句話。

不要在使用者沒有要求的情況下自動觸發這個流程；這是使用者主動執行 `/devlog-tracker:compact` 時才做的事。不要讀取或寫入 `.devlog/devlog.<name>.md` 具名檔（那是 `/devlog-tracker:keep` 的產物）。
