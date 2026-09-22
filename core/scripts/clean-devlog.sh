#!/usr/bin/env bash
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
. "$SCRIPT_DIR/devlog-md.sh"
. "$SCRIPT_DIR/json-field.sh"
. "$SCRIPT_DIR/devlog-lock.sh"
. "$SCRIPT_DIR/devlog-path.sh"

# Destructive and irreversible: only run when the caller has explicitly
# confirmed with the user first. This is a mechanical guard, not a
# replacement for that confirmation.
[ "${1:-}" = "--confirmed" ] || { echo "需要 --confirmed（使用者尚未確認，不要呼叫這支腳本）" >&2; exit 1; }

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_lock_acquire
trap 'devlog_lock_release' EXIT
MAIN="$DEVLOG_FILE"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
ROUND_CURRENT="$DEVLOG_DIR/.round-current.md"
# Post-split, devlog.md may legitimately not exist yet (a project's very
# first round can still be open, with real content sitting only in
# .round-current.md) — accept either devlog.md existing or .round-current.md
# having content to clean.
[ -f "$MAIN" ] || [ -s "$ROUND_CURRENT" ] || { echo "devlog.md 不存在" >&2; exit 1; }

HAS_OPEN=0
OPEN=""
if [ -f "$ROUND_OPEN" ]; then
  OPEN="$(json_int_get "$ROUND_OPEN" round)"
  [ -n "$OPEN" ] || { echo ".round-open 內容無法解析，未清空" >&2; exit 1; }
  [ -s "$ROUND_CURRENT" ] || { echo "找不到開著的 .round-current.md 內容，狀態可能不一致，未清空" >&2; exit 1; }
  HAS_OPEN=1
fi

if [ "$HAS_OPEN" -eq 1 ]; then
  # Keep the split's invariant intact: the open round's content stays in
  # .round-current.md (renumbered to Round 1), never in devlog.md. Writing
  # it into devlog.md here would leave .round-open pointing at a round
  # that Stop/close-open-round.sh can't find (they only ever look at
  # .round-current.md), silently disabling enforcement for the rest of
  # this turn and orphaning recovery on a crash.
  TMP_DIR="$(mktemp -d "$DEVLOG_DIR/.clean.XXXXXX")" || exit 1
  trap 'rm -rf "$TMP_DIR"; devlog_lock_release' EXIT
  NEW_CURRENT="$TMP_DIR/round-current.md"
  awk -v open="$OPEN" '
    NR == 1 && $0 ~ ("^## Round " open "([^0-9]|$)") { sub("^## Round " open, "## Round 1") }
    { print }
  ' "$ROUND_CURRENT" > "$NEW_CURRENT" || exit 1
  [ -s "$NEW_CURRENT" ] && grep -q '^## Round 1' "$NEW_CURRENT" || { echo "重寫結果異常，未寫入" >&2; exit 1; }
  mv "$NEW_CURRENT" "$ROUND_CURRENT" || exit 1
  rm -f "$MAIN" || exit 1
  rm -rf "$TMP_DIR"
  json_int_set "$ROUND_OPEN" round 1
  KEPT_ROUND=1
else
  rm -f "$MAIN" "$ROUND_CURRENT" || exit 1
  KEPT_ROUND=0
fi

rm -f "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.interrupted" "$DEVLOG_DIR/.awaiting-reply"
rm -f "$HANDOFF_FILE"
if [ -f "$DEVLOG_DIR/.checkpoint-state" ]; then
  json_int_set "$DEVLOG_DIR/.checkpoint-state" rounds_since_checkpoint 0
  json_int_set "$DEVLOG_DIR/.checkpoint-state" checkpoint_marker_count 0
fi

printf 'CLEANED KEPT_ROUND=%s\n' "$KEPT_ROUND"
exit 0
