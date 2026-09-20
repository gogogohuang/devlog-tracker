#!/usr/bin/env bash
# Self-check for lessons-on.sh / lessons-off.sh (docs/design/lessons-mode.md
# "Enable / disable"). No framework, plain assert-and-exit, matching this
# repo's existing style.
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
assert_file() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc"; FAIL=1; fi
}
assert_not_file() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc"; FAIL=1; fi
}

mkdir -p "$TMP_ROOT/.devlog"

# --- lessons-on without the main .enabled switch -> refuses ---------------
OUT="$(bash "$SCRIPT_DIR/lessons-on.sh")"
assert_exit "lessons-on without main switch -> exit 0 (advisory refusal, not a hard error)" 0 $?
case "$OUT" in
  *"NOT_ENABLED"*) echo "PASS: reports NOT_ENABLED when main switch is off" ;;
  *) echo "FAIL: expected NOT_ENABLED, got $OUT"; FAIL=1 ;;
esac
assert_not_file "no .lessons-enabled created without main switch" "$TMP_ROOT/.devlog/.lessons-enabled"

# --- lessons-on with the main switch present -> enables --------------------
touch "$TMP_ROOT/.devlog/.enabled"
OUT="$(bash "$SCRIPT_DIR/lessons-on.sh")"
assert_exit "lessons-on with main switch -> 0" 0 $?
assert_file ".lessons-enabled created" "$TMP_ROOT/.devlog/.lessons-enabled"
case "$OUT" in
  *"LESSONS_ENABLED="*) echo "PASS: reports LESSONS_ENABLED" ;;
  *) echo "FAIL: expected LESSONS_ENABLED=..., got $OUT"; FAIL=1 ;;
esac
assert_file ".lessons-advisory-state created alongside .lessons-enabled" "$TMP_ROOT/.devlog/.lessons-advisory-state"
grep -q '"count": 0' "$TMP_ROOT/.devlog/.lessons-advisory-state" \
  && echo "PASS: advisory count starts at 0" || { echo "FAIL: advisory count not 0"; FAIL=1; }
grep -q '"threshold": 3' "$TMP_ROOT/.devlog/.lessons-advisory-state" \
  && echo "PASS: advisory threshold defaults to 3" || { echo "FAIL: advisory threshold not 3"; FAIL=1; }

# --- lessons-on migrates an old .lessons-drift-state on re-run -------------
rm -f "$TMP_ROOT/.devlog/.lessons-advisory-state"
printf '%s\n' '{"mismatch_count": 2, "threshold": 7}' > "$TMP_ROOT/.devlog/.lessons-drift-state"
OUT="$(bash "$SCRIPT_DIR/lessons-on.sh")"
assert_exit "lessons-on migrates old state file -> 0" 0 $?
assert_file "migration produced .lessons-advisory-state" "$TMP_ROOT/.devlog/.lessons-advisory-state"
assert_not_file "migration removed .lessons-drift-state" "$TMP_ROOT/.devlog/.lessons-drift-state"
grep -q '"count": 2' "$TMP_ROOT/.devlog/.lessons-advisory-state" && echo "PASS: migrated count preserved" || { echo "FAIL: migrated count lost"; FAIL=1; }
grep -q '"threshold": 7' "$TMP_ROOT/.devlog/.lessons-advisory-state" && echo "PASS: migrated threshold preserved" || { echo "FAIL: migrated threshold lost"; FAIL=1; }

# --- lessons-off disables, leaves main switch and any lessons files alone --
echo 'keep me' > "$TMP_ROOT/.devlog/devlog.lessons.foo.md"
OUT="$(bash "$SCRIPT_DIR/lessons-off.sh")"
assert_exit "lessons-off -> 0" 0 $?
case "$OUT" in
  *"LESSONS_DISABLED"*) echo "PASS: reports LESSONS_DISABLED" ;;
  *) echo "FAIL: expected LESSONS_DISABLED, got $OUT"; FAIL=1 ;;
esac
assert_not_file ".lessons-enabled removed" "$TMP_ROOT/.devlog/.lessons-enabled"
assert_file "main .enabled untouched" "$TMP_ROOT/.devlog/.enabled"
assert_file "lessons file untouched" "$TMP_ROOT/.devlog/devlog.lessons.foo.md"
assert_file ".lessons-advisory-state untouched by lessons-off" "$TMP_ROOT/.devlog/.lessons-advisory-state"

# --- lessons-off when already off -> reports NOT_ENABLED, no error --------
OUT="$(bash "$SCRIPT_DIR/lessons-off.sh")"
assert_exit "lessons-off when already off -> 0" 0 $?
case "$OUT" in
  *"NOT_ENABLED"*) echo "PASS: lessons-off reports NOT_ENABLED when already off" ;;
  *) echo "FAIL: expected NOT_ENABLED, got $OUT"; FAIL=1 ;;
esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
