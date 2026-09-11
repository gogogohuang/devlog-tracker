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
# mid-turn auto-compact 改雜湊讓 Stop 靜默放行；compact 仍注入 excerpt
#（最後一個 Checkpoint + 最近兩輪 Summary/Handoff/Status），不 heal。
# close-open-round.sh 必須對 stdout 保持沉默。

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"

_src="${BASH_SOURCE[0]}"
HOOKS_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
# shellcheck source=detect-pending-question.sh
. "$HOOKS_DIR/detect-pending-question.sh"

INPUT="$(cat 2>/dev/null || true)"
SOURCE="$(json_str_field "$INPUT" source)"

case "$SOURCE" in
  startup|resume|clear|fork)
    if [ -f "$DEVLOG_DIR/.round-open" ]; then
      DANGLING_DETAIL=""
      if [ -n "$(detect_pending_question "$(json_str_field "$INPUT" transcript_path)")" ]; then
        DANGLING_DETAIL="awaiting_question"
      fi
      bash "$HOOKS_DIR/close-open-round.sh" "dangling:session_start" "$DANGLING_DETAIL" || true
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

echo "以下是本專案 .devlog/devlog.md 的接手摘要（不是全文；完整紀錄請自行讀取原檔）："
echo ""
awk '
  /^[ \t]*```/ { fence = !fence }
  {
    lines[NR] = $0
    infence[NR] = fence
  }
  END {
    n = NR
    last_cp = 0
    last_kept = 0
    rc = 0
    for (i = 1; i <= n; i++) {
      if (infence[i]) continue
      if (lines[i] ~ /^## Checkpoint/) last_cp = i
      if (lines[i] ~ /^## Kept 索引/) last_kept = i
      if (lines[i] ~ /^## Round /) { rc++; round_at[rc] = i }
    }
    if (last_cp > 0) {
      cp_end = n
      for (j = last_cp + 1; j <= n; j++) {
        if (!infence[j] && lines[j] ~ /^## /) { cp_end = j - 1; break }
      }
      for (j = last_cp; j <= cp_end; j++) print lines[j]
      print ""
    }
    if (last_kept > 0) {
      kp_end = n
      for (j = last_kept + 1; j <= n; j++) {
        if (!infence[j] && lines[j] ~ /^## /) { kp_end = j - 1; break }
      }
      for (j = last_kept; j <= kp_end; j++) print lines[j]
      print ""
    }
    start_i = (rc > 2) ? rc - 1 : 1
    if (rc == 0) exit 0
    for (r = start_i; r <= rc; r++) {
      rs = round_at[r]
      re = n
      for (j = rs + 1; j <= n; j++) {
        if (!infence[j] && lines[j] ~ /^## /) { re = j - 1; break }
      }
      print lines[rs]
      print ""
      has_summary = 0
      for (j = rs; j <= re; j++) if (!infence[j] && lines[j] ~ /^### Summary/) has_summary = 1
      keep = 0
      for (j = rs + 1; j <= re; j++) {
        if (infence[j]) {
          if (keep) print lines[j]
          continue
        }
        if (lines[j] ~ /^### Summary/ || lines[j] ~ /^### Handoff/ || lines[j] ~ /^### Status/) { keep = 1; print lines[j]; continue }
        if (lines[j] ~ /^### User Input/) { keep = (has_summary ? 0 : 1); if (keep) print lines[j]; continue }
        if (lines[j] ~ /^### /) { keep = 0; continue }
        if (keep) print lines[j]
      }
      print ""
    }
  }
' "$DEVLOG_FILE" 2>/dev/null || true
exit 0
