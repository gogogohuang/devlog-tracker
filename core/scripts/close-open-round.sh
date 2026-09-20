#!/usr/bin/env bash
# Stamp the open Round as INTERRUPTED. Always exit 0 (fail-open).
# Usage: close-open-round.sh <reason> [detail]
# The reason is written as a bracketed tag under Status (`[reason: ...]`) so
# it reads as internal debug metadata, not a broken/extra Status value — and
# stays visible even through a Markdown renderer (unlike an HTML comment,
# which a renderer would silently drop, losing the debug trail).
# detail (optional): "awaiting_question" makes the stub Summary/Handoff name
# the likely cause (interrupted while an AskUserQuestion answer was pending)
# instead of the generic "沒有正常收尾" — caller decides via
# detect-pending-question.sh; empty/unknown detail falls back to the generic
# stub, same as before.
# When detail is empty, the stub wording also depends on RECOVERED (did
# devlog.md change at all since the round's skeleton was written): if not,
# nothing was ever written back for this round (most likely the next prompt
# arrived before Claude engaged with it at all), so the stub says that
# plainly instead of implying work was interrupted mid-way.
# Silent on stdout — SessionStart injects stdout as additionalContext.
set -uo pipefail

REASON="${1:-unknown}"
DETAIL="${2:-}"

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_resolve_paths "$PROJECT_DIR"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
INTERRUPTED_FLAG="$DEVLOG_DIR/.interrupted"
ROUND_CURRENT="$DEVLOG_DIR/.round-current.md"
TURN_MARKER="$DEVLOG_DIR/.turn-start"

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

ROUND_OPEN_FILE="$(json_str_get "$ROUND_OPEN" file 2>/dev/null || true)"
if [ -n "$ROUND_OPEN_FILE" ] && [ "$ROUND_OPEN_FILE" != "${DEVLOG_FILE##*/}" ]; then
  # This marker belongs to a different branch's devlog file (e.g. the user
  # switched branches between round-start and now). Leave it untouched —
  # whichever branch it actually belongs to will resolve and close it
  # correctly when that branch is current again.
  exit 0
fi

OPEN_ROUND="$(json_int_get "$ROUND_OPEN" round)"
case "$OPEN_ROUND" in
  ''|*[!0-9]*) drop_markers; exit 0 ;;
esac

if [ ! -f "$ROUND_CURRENT" ] || [ ! -s "$ROUND_CURRENT" ]; then
  drop_markers
  exit 0
fi

RECOVERED=0
if [ -f "$TURN_MARKER" ]; then
  TURN_HASH="$(cat "$TURN_MARKER" 2>/dev/null || echo '')"
  CUR_HASH="$(cksum < "$ROUND_CURRENT" 2>/dev/null || echo '')"
  if [ -n "$TURN_HASH" ] && [ -n "$CUR_HASH" ] && [ "$CUR_HASH" != "$TURN_HASH" ]; then
    RECOVERED=1
  fi
fi

TMP="$ROUND_CURRENT.tmp"
awk -v reason="$REASON" -v detail="$DETAIL" -v recovered="$RECOVERED" '
  function summary_stub() {
    if (detail == "awaiting_question") return "這輪在等待使用者回答 AskUserQuestion 時結束，還沒收到答案。"
    if (recovered == 0) return "這一輪送出後，devlog.md 沒有留下任何後續處理紀錄就結束了。"
    return "這輪意外中斷。"
  }
  function reply_stub() {
    if (detail == "awaiting_question") return "（中斷前正在等使用者回答問題。）"
    if (recovered == 0) return "（這一輪在 devlog.md 裡沒有留下回覆紀錄。）"
    return "（這輪意外中斷，沒有對使用者完成回覆。）"
  }
  function handoff_stub() {
    if (detail == "awaiting_question") return "Claude 提了問題還在等回答，session 就先結束了；不是中途出錯，只是還沒收到答案。需要的話重新確認一次問題再繼續。"
    if (recovered == 0) return "這一輪沒有留下任何處理紀錄；下一步請看上面的 User Input 原文決定要不要接著處理。"
    return "這輪沒有正常收尾。"
  }
  { lines[NR] = $0; n = NR }
  END {
    has_s = 0
    has_r = 0
    has_h = 0
    for (i = 1; i <= n; i++) {
      if (lines[i] ~ /^### Summary/) has_s = 1
      if (lines[i] ~ /^### Reply/) has_r = 1
      if (lines[i] ~ /^### Handoff/) has_h = 1
    }
    # Recovered-complete still keys off Summary+Handoff (pre-Reply contract);
    # Stop will require Reply on the next normal close if missing.
    if (recovered && has_s && has_h) { exit 3 }

    skip_val = 0
    saw_status = 0
    for (i = 1; i <= n; i++) {
      if (skip_val) { skip_val = 0; continue }
      if (lines[i] ~ /^### Status/) {
        saw_status = 1
        if (!has_s) {
          print "### Summary"
          print summary_stub()
          print ""
        }
        if (!has_r) {
          print "### Reply"
          print reply_stub()
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
        print "[reason: " reason "]"
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
      if (!has_r) {
        print "### Reply"
        print reply_stub()
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
      print "[reason: " reason "]"
    }
  }
' "$ROUND_CURRENT" > "$TMP" 2>/dev/null
AWK_RC=$?
if [ "$AWK_RC" -eq 0 ]; then
  mv "$TMP" "$ROUND_CURRENT" 2>/dev/null || true
else
  rm -f "$TMP" 2>/dev/null || true
fi
if [ "$AWK_RC" -eq 0 ] || [ "$AWK_RC" -eq 3 ]; then
  # 只有併入真的成功才清掉 .round-open：併入失敗（例如寫入失敗）時保留它，
  # 讓下一次 dangling-heal（下一則訊息／下次 SessionStart 都會跑到）還有
  # 機會重試，而不是內容被孤立在 .round-current.md 卻沒有任何機制知道要去
  # 救它。.interrupted 這個訊號本身已經處理完，兩種結果都清掉。
  if devlog_merge_round_current "$DEVLOG_FILE" "$ROUND_CURRENT"; then
    drop_markers
  else
    rm -f "$INTERRUPTED_FLAG" 2>/dev/null || true
  fi
else
  drop_markers
fi
exit 0
