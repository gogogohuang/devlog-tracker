#!/usr/bin/env bash
# SessionStart hook：在 startup / resume / clear / compact / fork 時執行
# 讀取目前工作目錄下的 .devlog/devlog.md，只取最後 N 輪 + 開頭摘要（如果有），
# 印到 stdout 讓 Claude Code 自動注入這次 session 的 context。
# 找不到檔案就直接 exit 0，不輸出任何東西（不干擾一般沒有用 devlog 的專案）。
#
# Span Mode：如果 .devlog/.span-open 還開著（見 SKILL.md），在最前面加一段
# 提醒，不管 devlog.md 存不存在都要顯示——讀不到／格式壞掉就靜默跳過，
# 跟這支腳本一貫的 fail-open 原則一致。
#
# Dangling heal：只在真正的 session 邊界（startup / resume / clear / fork）
# 把殘留的 .round-open 標成 INTERRUPTED。mid-turn auto-compact 也會觸發
# SessionStart（source=compact），此時若 heal 會改雜湊、加 stub，讓隨後的
# Stop 靜默放行——因此 compact（以及 source 缺失／讀不到）一律跳過 heal，
# 但仍照常注入最近 8 輪。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"
MAX_ROUNDS=8

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT="$(cat 2>/dev/null || true)"
SOURCE=""
if command -v jq >/dev/null 2>&1; then
  SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || echo '')"
  if [ "$SOURCE" = "null" ]; then SOURCE=""; fi
else
  SOURCE="$(printf '%s' "$INPUT" | grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi

case "$SOURCE" in
  startup|resume|clear|fork)
    if [ -f "$DEVLOG_DIR/.round-open" ]; then
      bash "$HOOKS_DIR/close-open-round.sh" "dangling:session_start" || true
    fi
    ;;
esac

if [ -f "$SPAN_FILE" ]; then
  SPAN_ROUND="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$SPAN_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  SPAN_OPENED_AT_RAW="$(grep -o '"opened_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$SPAN_FILE" 2>/dev/null || echo '')"
  SPAN_OPENED_AT=""
  if [ -n "$SPAN_OPENED_AT_RAW" ]; then
    SPAN_OPENED_AT="$(printf '%s' "$SPAN_OPENED_AT_RAW" | sed -E 's/^.*:[[:space:]]*"//; s/"$//' 2>/dev/null || echo '')"
  fi
  if [ -n "$SPAN_ROUND" ] && [ -n "$SPAN_OPENED_AT" ]; then
    echo "⚠️ 有一個開啟中的 span：Round ${SPAN_ROUND}，從 ${SPAN_OPENED_AT} 開始，"
    echo "還沒有正式結束。請先確認要繼續這個自動化任務，還是要明確關閉它"
    echo "（刪除 .devlog/.span-open 並補寫收尾的 Round）。"
    echo ""
  fi
fi

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
