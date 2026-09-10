#!/usr/bin/env bash
# Stamp the open Round as INTERRUPTED. Always exit 0 (fail-open).
# Usage: close-open-round.sh <reason> [detail]
# The reason is written as an HTML comment under Status (`<!-- reason: ... -->`)
# so it reads as internal debug metadata, not a broken/extra Status value —
# devlog.md is meant to be read by a human without touching hook internals.
# detail (optional): "awaiting_question" makes the stub Summary/Handoff name
# the likely cause (interrupted while an AskUserQuestion answer was pending)
# instead of the generic "沒有正常收尾" — caller decides via
# detect-pending-question.sh; empty/unknown detail falls back to the generic
# stub, same as before.
# Silent on stdout — SessionStart injects stdout as additionalContext.
set -uo pipefail

REASON="${1:-unknown}"
DETAIL="${2:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
INTERRUPTED_FLAG="$DEVLOG_DIR/.interrupted"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
TURN_MARKER="$DEVLOG_DIR/.turn-start"

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"

drop_markers() {
  rm -f "$ROUND_OPEN" "$INTERRUPTED_FLAG" 2>/dev/null || true
}

[ -f "$ENABLED_FLAG" ] || exit 0
devlog_lock_acquire
trap 'devlog_lock_release' EXIT
if [ ! -f "$ROUND_OPEN" ]; then
  rm -f "$INTERRUPTED_FLAG" 2>/dev/null || true
  exit 0
fi

OPEN_ROUND="$(json_int_get "$ROUND_OPEN" round)"
case "$OPEN_ROUND" in
  ''|*[!0-9]*) drop_markers; exit 0 ;;
esac

if [ ! -f "$DEVLOG_FILE" ]; then
  drop_markers
  exit 0
fi

RECOVERED=0
if [ -f "$TURN_MARKER" ]; then
  TURN_HASH="$(cat "$TURN_MARKER" 2>/dev/null || echo '')"
  CUR_HASH="$(cksum < "$DEVLOG_FILE" 2>/dev/null || echo '')"
  if [ -n "$TURN_HASH" ] && [ -n "$CUR_HASH" ] && [ "$CUR_HASH" != "$TURN_HASH" ]; then
    RECOVERED=1
  fi
fi

TMP="$DEVLOG_FILE.tmp"
awk -v want="$OPEN_ROUND" -v reason="$REASON" -v detail="$DETAIL" -v recovered="$RECOVERED" '
  function summary_stub() {
    if (detail == "awaiting_question") return "這輪在等待使用者回答 AskUserQuestion 時結束，還沒收到答案。"
    return "這輪意外中斷。"
  }
  function handoff_stub() {
    if (detail == "awaiting_question") return "Claude 提了問題還在等回答，session 就先結束了；不是中途出錯，只是還沒收到答案。需要的話重新確認一次問題再繼續。"
    return "這輪沒有正常收尾。"
  }
  /^[ \t]*```/ { fence = !fence }
  !fence && /^## Round / { last_start = NR }
  { lines[NR] = $0; infence[NR] = fence; n = NR }
  END {
    if (last_start == 0) { exit 2 }
    last_end = n
    for (i = last_start + 1; i <= n; i++) {
      if (!infence[i] && lines[i] ~ /^## /) { last_end = i - 1; break }
    }
    split(lines[last_start], parts, /[ \t]+/)
    rn = parts[3] + 0
    if (rn != want + 0) { exit 2 }

    has_s = 0
    has_h = 0
    for (i = last_start; i <= last_end; i++) {
      if (lines[i] ~ /^### Summary/) has_s = 1
      if (lines[i] ~ /^### Handoff/) has_h = 1
    }
    if (recovered && has_s && has_h) { exit 3 }

    skip_val = 0
    saw_status = 0
    for (i = 1; i <= n; i++) {
      if (i < last_start || i > last_end) { print lines[i]; continue }
      if (skip_val) { skip_val = 0; continue }
      if (lines[i] ~ /^### Status/) {
        saw_status = 1
        if (!has_s) {
          print "### Summary"
          print summary_stub()
          print ""
        }
        if (!has_h) {
          print "### Handoff"
          print "#### 現況"
          print handoff_stub()
          print ""
        }
        print "### Status"
        print "INTERRUPTED"
        print "<!-- reason: " reason " -->"
        skip_val = 1
        continue
      }
      print lines[i]
    }
    if (!saw_status) {
      if (!has_s) {
        print "### Summary"
        print summary_stub()
        print ""
      }
      if (!has_h) {
        print "### Handoff"
        print "#### 現況"
        print handoff_stub()
        print ""
      }
      print "### Status"
      print "INTERRUPTED"
      print "<!-- reason: " reason " -->"
    }
  }
' "$DEVLOG_FILE" > "$TMP" 2>/dev/null
AWK_RC=$?
if [ "$AWK_RC" -eq 0 ]; then
  mv "$TMP" "$DEVLOG_FILE" 2>/dev/null || true
else
  rm -f "$TMP" 2>/dev/null || true
fi
drop_markers
exit 0
