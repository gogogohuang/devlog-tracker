#!/usr/bin/env bash
# Self-check for segment-watch-set.sh. Run:
#   bash hooks/scripts/test-segment-watch-set.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export CLAUDE_PROJECT_DIR="$TMP_ROOT"
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected $expected got $actual)"; FAIL=1; fi
}

# --- 1: never started -> NOT_STARTED, no files created ----------------------
OUT="$(bash "$SCRIPT_DIR/segment-watch-set.sh" 300)"
assert_exit "never started -> exit 0" 0 $?
case "$OUT" in
  *"NOT_STARTED"*) echo "PASS: reports NOT_STARTED" ;;
  *) echo "FAIL: expected NOT_STARTED, got $OUT"; FAIL=1 ;;
esac
if [ -e "$TMP_ROOT/.devlog" ]; then
  echo "FAIL: NOT_STARTED path should not create .devlog"; FAIL=1
else
  echo "PASS: NOT_STARTED path creates no .devlog"
fi

mkdir -p "$TMP_ROOT/.devlog"
touch "$TMP_ROOT/.devlog/.enabled"

# --- 2: started, no .segment-state yet -> creates one with the given value --
OUT="$(bash "$SCRIPT_DIR/segment-watch-set.sh" 300)"
assert_exit "fresh set -> exit 0" 0 $?
grep -q '"max_silent_seconds": 300' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: fresh set writes 300" || { echo "FAIL: fresh set"; FAIL=1; }
case "$OUT" in
  *"SEGMENT_MAX_SILENT_SECONDS=300"*) echo "PASS: fresh set reports 300" ;;
  *) echo "FAIL: expected SEGMENT_MAX_SILENT_SECONDS=300, got $OUT"; FAIL=1 ;;
esac

# --- 3: started, existing .segment-state -> overrides just the threshold ----
printf '%s\n' '{"last_change_epoch": 42, "last_seen_cksum": "abc", "max_silent_seconds": 300, "session_id": "s1"}' \
  > "$TMP_ROOT/.devlog/.segment-state"
OUT="$(bash "$SCRIPT_DIR/segment-watch-set.sh" 120)"
assert_exit "override set -> exit 0" 0 $?
grep -q '"max_silent_seconds": 120' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: override set writes 120" || { echo "FAIL: override set"; FAIL=1; }
grep -q '"last_change_epoch": 42' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: override set keeps last_change_epoch" || { echo "FAIL: last_change_epoch clobbered"; FAIL=1; }
grep -q '"session_id": "s1"' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: override set keeps session_id" || { echo "FAIL: session_id clobbered"; FAIL=1; }
case "$OUT" in
  *"SEGMENT_MAX_SILENT_SECONDS=120"*) echo "PASS: override set reports 120" ;;
  *) echo "FAIL: expected SEGMENT_MAX_SILENT_SECONDS=120, got $OUT"; FAIL=1 ;;
esac

# --- 4: invalid seconds rejected, state untouched ---------------------------
BEFORE="$(cat "$TMP_ROOT/.devlog/.segment-state")"
bash "$SCRIPT_DIR/segment-watch-set.sh" abc >/dev/null 2>"$TMP_ROOT/err"
assert_exit "bad arg -> exit 1" 1 $?
AFTER="$(cat "$TMP_ROOT/.devlog/.segment-state")"
if [ "$BEFORE" = "$AFTER" ]; then echo "PASS: bad arg leaves segment-state untouched"
else echo "FAIL: bad arg changed segment-state"; FAIL=1; fi
[ -s "$TMP_ROOT/err" ] && echo "PASS: bad arg prints stderr" || { echo "FAIL: bad arg silent"; FAIL=1; }

bash "$SCRIPT_DIR/segment-watch-set.sh" 0 >/dev/null 2>&1
assert_exit "zero -> exit 1" 1 $?

bash "$SCRIPT_DIR/segment-watch-set.sh" >/dev/null 2>&1
assert_exit "missing arg -> exit 1" 1 $?

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
