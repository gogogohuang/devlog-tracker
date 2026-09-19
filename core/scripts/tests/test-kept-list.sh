#!/usr/bin/env bash
# Self-check for kept-list.sh (docs/design/keep.md "Kept index" +
# /devlog-tracker:overview). Plain read only -- no workspace verification.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"
FAIL=0
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected $expected got $actual)"; FAIL=1; fi
}

# --- No devlog.md at all -> NO_INDEX ----------------------------------------
OUT="$(bash "$SCRIPT_DIR/kept-list.sh" 2>&1)"
assert_exit "no devlog.md -> 0" 0 $?
case "$OUT" in
  *"NO_INDEX"*) echo "PASS: reports NO_INDEX when devlog.md is absent" ;;
  *) echo "FAIL: expected NO_INDEX, got $OUT"; FAIL=1 ;;
esac

# --- devlog.md exists but no Kept 索引 -> NO_INDEX --------------------------
echo '## Round 1 — 2026-09-12T00:00:00+08:00

### Summary
fixture

### Handoff
#### 現況
fixture

### Status
DONE' > "$DEVLOG_DIR/devlog.md"
OUT="$(bash "$SCRIPT_DIR/kept-list.sh" 2>&1)"
assert_exit "devlog.md with no index -> 0" 0 $?
case "$OUT" in
  *"NO_INDEX"*) echo "PASS: reports NO_INDEX when no Kept 索引 block exists" ;;
  *) echo "FAIL: expected NO_INDEX, got $OUT"; FAIL=1 ;;
esac

# --- Kept 索引 present, target file exists -> EXISTS=1 ----------------------
printf 'kept content\n' > "$DEVLOG_DIR/devlog.foo-bar.md"
printf '\n## Kept 索引\n- `devlog.foo-bar.md`：Round 1-1，kept_at 2026-09-12T00:00:00+08:00，foo bar 主題\n' >> "$DEVLOG_DIR/devlog.md"
OUT="$(bash "$SCRIPT_DIR/kept-list.sh" 2>&1)"
assert_exit "index with one existing file -> 0" 0 $?
case "$OUT" in
  *"FILE="*"devlog.foo-bar.md"*"EXISTS=1"*) echo "PASS: existing kept file reported with EXISTS=1" ;;
  *) echo "FAIL: expected FILE=...devlog.foo-bar.md EXISTS=1, got $OUT"; FAIL=1 ;;
esac

# --- Ghost row: index line present, file missing on disk -> EXISTS=0 -------
rm -f "$DEVLOG_DIR/devlog.foo-bar.md"
OUT="$(bash "$SCRIPT_DIR/kept-list.sh" 2>&1)"
assert_exit "ghost row -> 0" 0 $?
case "$OUT" in
  *"FILE="*"devlog.foo-bar.md"*"EXISTS=0"*) echo "PASS: ghost kept file reported with EXISTS=0" ;;
  *) echo "FAIL: expected FILE=...devlog.foo-bar.md EXISTS=0, got $OUT"; FAIL=1 ;;
esac

# --- Multiple entries listed, one per line -----------------------------------
printf 'kept content two\n' > "$DEVLOG_DIR/devlog.second-topic.md"
sed -i.bak '$ a\
- `devlog.second-topic.md`：Round 2-2，kept_at 2026-09-13T00:00:00+08:00
' "$DEVLOG_DIR/devlog.md"
rm -f "$DEVLOG_DIR/devlog.md.bak"
OUT="$(bash "$SCRIPT_DIR/kept-list.sh" 2>&1)"
assert_exit "index with two entries -> 0" 0 $?
LINE_COUNT="$(printf '%s\n' "$OUT" | grep -c '^FILE=')"
[ "$LINE_COUNT" -eq 2 ] && echo "PASS: two FILE= lines printed for two index entries" || { echo "FAIL: expected 2 FILE= lines, got $LINE_COUNT"; FAIL=1; }
case "$OUT" in
  *"devlog.second-topic.md"*"EXISTS=1"*) echo "PASS: second-topic file reported with EXISTS=1" ;;
  *) echo "FAIL: expected devlog.second-topic.md EXISTS=1, got $OUT"; FAIL=1 ;;
esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
