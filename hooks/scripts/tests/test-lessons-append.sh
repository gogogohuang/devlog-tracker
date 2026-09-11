#!/usr/bin/env bash
# Self-check for lessons-append.sh (docs/design/lessons-mode.md "Storage" /
# "## Lessons 索引" / "Write mechanism"). No framework, plain
# assert-and-exit, matching this repo's existing style.
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

echo '## Round 1 — 2026-09-12T00:00:00+08:00

### Summary
fixture

### Handoff
#### 現況
fixture

### Status
DONE' > "$DEVLOG_DIR/devlog.md"

# --- Refused without the main switch ---------------------------------------
OUT="$(bash "$SCRIPT_DIR/lessons-append.sh" --topic foo --text "x" 2>&1)"
assert_exit "no .enabled -> exit 1" 1 $?
case "$OUT" in
  *"NOT_ENABLED"*) echo "PASS: reports NOT_ENABLED" ;;
  *) echo "FAIL: expected NOT_ENABLED, got $OUT"; FAIL=1 ;;
esac

touch "$DEVLOG_DIR/.enabled"

# --- Refused without lessons-enabled ---------------------------------------
OUT="$(bash "$SCRIPT_DIR/lessons-append.sh" --topic foo --text "x" 2>&1)"
assert_exit "enabled but lessons off -> exit 1" 1 $?
case "$OUT" in
  *"LESSONS_NOT_ENABLED"*) echo "PASS: reports LESSONS_NOT_ENABLED" ;;
  *) echo "FAIL: expected LESSONS_NOT_ENABLED, got $OUT"; FAIL=1 ;;
esac

touch "$DEVLOG_DIR/.lessons-enabled"

# --- Missing --text ----------------------------------------------------------
bash "$SCRIPT_DIR/lessons-append.sh" --topic foo >/dev/null 2>&1
assert_exit "missing --text -> exit 1" 1 $?

# --- Invalid topic (path traversal) -----------------------------------------
bash "$SCRIPT_DIR/lessons-append.sh" --topic "../etc" --text "x" >/dev/null 2>&1
assert_exit "path-traversal topic -> exit 1" 1 $?

# --- Reserved topic names ----------------------------------------------------
bash "$SCRIPT_DIR/lessons-append.sh" --topic "archive" --text "x" >/dev/null 2>&1
assert_exit "topic 'archive' rejected -> exit 1" 1 $?
bash "$SCRIPT_DIR/lessons-append.sh" --topic "lessons" --text "x" >/dev/null 2>&1
assert_exit "topic 'lessons' rejected -> exit 1" 1 $?

# --- First entry creates the topic file and the header ----------------------
OUT="$(bash "$SCRIPT_DIR/lessons-append.sh" --topic "keep-move-bug" --text "第一次卡在 keep-move.sh 沒處理缺號範圍。後來改成逐一檢查連續性。")"
assert_exit "first entry -> 0" 0 $?
case "$OUT" in
  *"PATH=.devlog/devlog.lessons.keep-move-bug.md"*) echo "PASS: reports PATH" ;;
  *) echo "FAIL: expected PATH=..., got $OUT"; FAIL=1 ;;
esac
TARGET="$DEVLOG_DIR/devlog.lessons.keep-move-bug.md"
if [ -f "$TARGET" ]; then echo "PASS: topic file created"; else echo "FAIL: topic file missing"; FAIL=1; fi
grep -q '^# Lessons: keep-move-bug$' "$TARGET" && echo "PASS: header present" || { echo "FAIL: header missing"; FAIL=1; }
grep -q '^## 2026-\|^## [0-9]' "$TARGET" && echo "PASS: timestamped entry heading present" || { echo "FAIL: no entry heading"; FAIL=1; }
grep -q '第一次卡在 keep-move.sh' "$TARGET" && echo "PASS: entry text present" || { echo "FAIL: entry text missing"; FAIL=1; }

# --- devlog.<name>.md / .md normalization on --topic input ------------------
OUT2="$(bash "$SCRIPT_DIR/lessons-append.sh" --topic "devlog.lessons.keep-move-bug.md" --text "第二筆，測試正規化。")"
assert_exit "prefixed/suffixed topic input normalizes to the same file -> 0" 0 $?
ENTRY_COUNT="$(grep -c '^## ' "$TARGET")"
if [ "$ENTRY_COUNT" = "2" ]; then
  echo "PASS: second call appended to the SAME file (normalization collapsed devlog.lessons.<x>.md to <x>)"
else
  echo "FAIL: expected 2 entries in one file, got $ENTRY_COUNT (normalization likely created a second file)"
  FAIL=1
fi

# --- Lessons 索引 rebuilt: one line, correct count and latest title ---------
INDEX_BLOCK="$(awk '/^## Lessons 索引/{grab=1;next} grab{print}' "$DEVLOG_DIR/devlog.md")"
case "$INDEX_BLOCK" in
  *"devlog.lessons.keep-move-bug.md"*"2 則"*"第二筆，測試正規化。"*)
    echo "PASS: index line has file, count=2, and latest entry's title" ;;
  *)
    echo "FAIL: unexpected index block: $INDEX_BLOCK"; FAIL=1 ;;
esac

# --- A second topic gets its own file and its own index line ----------------
bash "$SCRIPT_DIR/lessons-append.sh" --topic "span-mode-detour" --text "一開始想在 hook 裡分辨自動續接跟真人插話，後來確認做不到，改成明確標記。" >/dev/null
INDEX_BLOCK2="$(awk '/^## Lessons 索引/{grab=1;next} grab{print}' "$DEVLOG_DIR/devlog.md")"
LINE_COUNT="$(printf '%s\n' "$INDEX_BLOCK2" | grep -c '^- `devlog.lessons\.')"
if [ "$LINE_COUNT" = "2" ]; then
  echo "PASS: index has one line per topic file (2 topics -> 2 lines)"
else
  echo "FAIL: expected 2 index lines, got $LINE_COUNT: $INDEX_BLOCK2"
  FAIL=1
fi
case "$INDEX_BLOCK2" in
  *"devlog.lessons.span-mode-detour.md"*"1 則"*) echo "PASS: second topic's own line present" ;;
  *) echo "FAIL: second topic missing from index: $INDEX_BLOCK2"; FAIL=1 ;;
esac

# --- Index rebuild never duplicates the heading -----------------------------
HEADING_COUNT="$(grep -c '^## Lessons 索引' "$DEVLOG_DIR/devlog.md")"
if [ "$HEADING_COUNT" = "1" ]; then
  echo "PASS: exactly one '## Lessons 索引' heading after multiple appends"
else
  echo "FAIL: expected exactly one heading, got $HEADING_COUNT"
  FAIL=1
fi

# --- Title truncates at the first 。/. -------------------------------------
bash "$SCRIPT_DIR/lessons-append.sh" --topic "punct" --text "先卡住了。後來才發現是路徑問題，多寫了一段沒用的重試邏輯。" >/dev/null
INDEX_BLOCK3="$(awk '/^## Lessons 索引/{grab=1;next} grab{print}' "$DEVLOG_DIR/devlog.md")"
case "$INDEX_BLOCK3" in
  *"「先卡住了。」"*) echo "PASS: title truncated at first 。" ;;
  *) echo "FAIL: expected title truncated at first 。, got: $INDEX_BLOCK3"; FAIL=1 ;;
esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
