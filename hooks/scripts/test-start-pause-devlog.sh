#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# start on empty project
OUT="$(bash "$SCRIPT_DIR/start-devlog.sh")"
assert_exit "start empty -> 0" 0 $?
assert_file ".enabled" "$TMP_ROOT/.devlog/.enabled"
assert_file "checkpoint" "$TMP_ROOT/.devlog/.checkpoint-state"
assert_file "segment" "$TMP_ROOT/.devlog/.segment-state"
assert_not_file "no devlog.md created" "$TMP_ROOT/.devlog/devlog.md"
case "$OUT" in
  *"GITIGNORE_DEVLOG=no"*) echo "PASS: reports missing gitignore entry" ;;
  *) echo "FAIL: expected GITIGNORE_DEVLOG=no, got $OUT"; FAIL=1 ;;
esac
grep -q '"max_silent_rounds": 20' "$TMP_ROOT/.devlog/.checkpoint-state" \
  && echo "PASS: default checkpoint" || { echo "FAIL: checkpoint defaults"; FAIL=1; }
grep -q '"max_silent_seconds": 900' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: default segment" || { echo "FAIL: segment defaults"; FAIL=1; }
grep -q '"session_id": ""' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: default segment session id" || { echo "FAIL: segment session id"; FAIL=1; }

# preserve thresholds on second start
printf '%s\n' '{"rounds_since_checkpoint": 7, "max_silent_rounds": 3, "checkpoint_marker_count": 1}' \
  > "$TMP_ROOT/.devlog/.checkpoint-state"
printf '%s\n' '{"last_change_epoch": 1, "last_seen_cksum": "x", "max_silent_seconds": 60}' \
  > "$TMP_ROOT/.devlog/.segment-state"
bash "$SCRIPT_DIR/start-devlog.sh" >/dev/null
grep -q '"max_silent_rounds": 3' "$TMP_ROOT/.devlog/.checkpoint-state" \
  && echo "PASS: start does not reset max_silent_rounds" || { echo "FAIL: checkpoint reset"; FAIL=1; }
grep -q '"max_silent_seconds": 60' "$TMP_ROOT/.devlog/.segment-state" \
  && echo "PASS: start does not reset max_silent_seconds" || { echo "FAIL: segment reset"; FAIL=1; }

# gitignore already has .devlog/
echo '.devlog/' > "$TMP_ROOT/.gitignore"
OUT="$(bash "$SCRIPT_DIR/start-devlog.sh")"
case "$OUT" in
  *"GITIGNORE_DEVLOG=yes"*) echo "PASS: detects gitignore entry" ;;
  *) echo "FAIL: expected GITIGNORE_DEVLOG=yes, got $OUT"; FAIL=1 ;;
esac

# pause
touch "$TMP_ROOT/.devlog/.span-open" "$TMP_ROOT/.devlog/.round-open" "$TMP_ROOT/.devlog/.interrupted"
echo 'keep me' > "$TMP_ROOT/.devlog/devlog.md"
OUT="$(bash "$SCRIPT_DIR/pause-devlog.sh")"
assert_exit "pause -> 0" 0 $?
assert_not_file "enabled gone" "$TMP_ROOT/.devlog/.enabled"
assert_not_file "span gone" "$TMP_ROOT/.devlog/.span-open"
assert_not_file "round-open gone" "$TMP_ROOT/.devlog/.round-open"
assert_not_file "interrupted gone" "$TMP_ROOT/.devlog/.interrupted"
assert_file "log kept" "$TMP_ROOT/.devlog/devlog.md"
assert_file "checkpoint kept" "$TMP_ROOT/.devlog/.checkpoint-state"

# pause when never started
rm -rf "$TMP_ROOT/.devlog"
OUT="$(bash "$SCRIPT_DIR/pause-devlog.sh")"
assert_exit "pause never-started -> 0" 0 $?
case "$OUT" in
  *"NOT_ENABLED"*) echo "PASS: pause reports NOT_ENABLED" ;;
  *) echo "FAIL: expected NOT_ENABLED, got $OUT"; FAIL=1 ;;
esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
