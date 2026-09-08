#!/usr/bin/env bash
# SessionStart hook：在 startup / resume / clear / compact 時執行
# 讀取目前工作目錄下的 .devlog/devlog.md，只取最後 N 輪 + 開頭摘要（如果有），
# 印到 stdout 讓 Claude Code 自動注入這次 session 的 context。
# 找不到檔案就直接 exit 0，不輸出任何東西（不干擾一般沒有用 devlog 的專案）。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_FILE="$PROJECT_DIR/.devlog/devlog.md"
MAX_ROUNDS=8

[ -f "$DEVLOG_FILE" ] || exit 0

echo "以下是本專案 .devlog/devlog.md 目前的內容，用來接續先前的工作進度（只顯示最近 ${MAX_ROUNDS} 輪，完整紀錄請自行讀取原檔）："
echo ""

awk -v max="$MAX_ROUNDS" '
  BEGIN { n = 0 }
  /^## Round / { n++; buf[n] = "" }
  {
    if (n > 0) { buf[n] = buf[n] $0 "\n" }
    else       { preamble = preamble $0 "\n" }
  }
  END {
    if (preamble != "") { printf "%s\n", preamble }
    start = (n > max) ? (n - max + 1) : 1
    for (i = start; i <= n; i++) { printf "%s", buf[i] }
  }
' "$DEVLOG_FILE" 2>/dev/null || true

exit 0
