#!/usr/bin/env bash
# Self-check for lessons-read.sh (docs/design/lessons-mode.md "Reading
# lessons on demand"). No framework, plain assert-and-exit.
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

# --- No devlog.md at all, no topic -> NO_INDEX ------------------------------
OUT="$(bash "$SCRIPT_DIR/lessons-read.sh" 2>&1)"
assert_exit "no devlog.md, no topic -> 0" 0 $?
case "$OUT" in
  *"NO_INDEX"*) echo "PASS: reports NO_INDEX when devlog.md is absent" ;;
  *) echo "FAIL: expected NO_INDEX, got $OUT"; FAIL=1 ;;
esac

# --- devlog.md exists but no Lessons 索引 -> NO_INDEX -----------------------
echo '## Round 1 — 2026-09-12T00:00:00+08:00

### Summary
fixture

### Handoff
#### 現況
fixture

### Status
DONE' > "$DEVLOG_DIR/devlog.md"
OUT="$(bash "$SCRIPT_DIR/lessons-read.sh" 2>&1)"
assert_exit "devlog.md with no index, no topic -> 0" 0 $?
case "$OUT" in
  *"NO_INDEX"*) echo "PASS: reports NO_INDEX when no Lessons 索引 block exists" ;;
  *) echo "FAIL: expected NO_INDEX, got $OUT"; FAIL=1 ;;
esac

# --- Index present -> printed verbatim, no topic ----------------------------
touch "$DEVLOG_DIR/.enabled" "$DEVLOG_DIR/.lessons-enabled"
bash "$SCRIPT_DIR/lessons-append.sh" --topic "foo-bar" --text "教訓內容一。" >/dev/null
OUT="$(bash "$SCRIPT_DIR/lessons-read.sh" 2>&1)"
assert_exit "index present, no topic -> 0" 0 $?
case "$OUT" in
  *"devlog.lessons.foo-bar.md"*) echo "PASS: index line for foo-bar printed" ;;
  *) echo "FAIL: expected index line, got $OUT"; FAIL=1 ;;
esac

# --- Read a specific existing topic, full content ---------------------------
OUT="$(bash "$SCRIPT_DIR/lessons-read.sh" "foo-bar" 2>&1)"
assert_exit "read existing topic -> 0" 0 $?
case "$OUT" in
  *"PATH=.devlog/devlog.lessons.foo-bar.md"*) echo "PASS: reports PATH" ;;
  *) echo "FAIL: expected PATH=..., got $OUT"; FAIL=1 ;;
esac
case "$OUT" in
  *"教訓內容一。"*) echo "PASS: full entry text returned" ;;
  *) echo "FAIL: expected entry text, got $OUT"; FAIL=1 ;;
esac

# --- devlog.lessons.<x>.md / .md input normalizes the same as --topic -------
OUT="$(bash "$SCRIPT_DIR/lessons-read.sh" "devlog.lessons.foo-bar.md" 2>&1)"
assert_exit "read with devlog.lessons.<x>.md input -> 0" 0 $?
case "$OUT" in
  *"PATH=.devlog/devlog.lessons.foo-bar.md"*) echo "PASS: normalized input reads the same file" ;;
  *) echo "FAIL: expected same PATH, got $OUT"; FAIL=1 ;;
esac

# --- Missing topic -> MISSING + candidates ----------------------------------
bash "$SCRIPT_DIR/lessons-append.sh" --topic "another-topic" --text "教訓內容二。" >/dev/null
OUT="$(bash "$SCRIPT_DIR/lessons-read.sh" "does-not-exist" 2>&1)"
assert_exit "missing topic -> exit 1" 1 $?
case "$OUT" in
  *"MISSING"*) echo "PASS: reports MISSING" ;;
  *) echo "FAIL: expected MISSING, got $OUT"; FAIL=1 ;;
esac
case "$OUT" in
  *"CANDIDATES="*"foo-bar"*"another-topic"*|*"CANDIDATES="*"another-topic"*"foo-bar"*)
    echo "PASS: candidates list both existing topics" ;;
  *) echo "FAIL: expected candidates listing both topics, got $OUT"; FAIL=1 ;;
esac

# --- Path traversal in topic -> rejected -------------------------------------
bash "$SCRIPT_DIR/lessons-read.sh" "../etc" >/dev/null 2>&1
assert_exit "path-traversal topic -> exit 1" 1 $?

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
