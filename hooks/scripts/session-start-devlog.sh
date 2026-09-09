#!/usr/bin/env bash
# SessionStart hook：在 startup / resume / clear / compact / fork 時執行。
# startup / resume / compact / fork：讀 .devlog/devlog.md 最後 N 輪 + 開頭摘要，
# 印到 stdout 讓 Claude Code 當成 additionalContext 注入。
# source=clear：只做 dangling heal，不注入、不印 span 提醒——/clear 必須是真的空
# context，接續改由 /devlog-tracker:continue。找不到檔案就 exit 0。
#
# Span Mode：.span-open 還開著時，在注入內容最前面加一段提醒（clear 除外）。
# 讀不到／格式壞掉就靜默跳過，fail-open。
#
# Dangling heal：startup / resume / clear / fork 把殘留的 .round-open 標成
# INTERRUPTED。source=compact（以及 source 缺失／讀不到）跳過 heal，避免
# mid-turn auto-compact 改雜湊讓 Stop 靜默放行；compact 仍注入最近 8 輪。
# close-open-round.sh 必須對 stdout 保持沉默。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"
MAX_ROUNDS=8

_src="${BASH_SOURCE[0]}"
HOOKS_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"

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

# /clear 清空對話；不要把 devlog 或 span 提醒打回 context。
if [ "$SOURCE" = "clear" ]; then
  exit 0
fi

if [ -f "$SPAN_FILE" ]; then
  SPAN_ROUND="$(json_int_get "$SPAN_FILE" round)"
  SPAN_OPENED_AT="$(json_str_get "$SPAN_FILE" opened_at)"
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
