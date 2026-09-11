#!/usr/bin/env bash
# Self-check for enforce-devlog.sh's #### 檔案 machine-verify (Phase 4,
# docs/design/files-verify.md). Separate file from test-enforce-devlog.sh
# and test-enforce-devlog-workspace.sh; still auto-discovered by
# run-tests.sh's tests/test-*.sh glob.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"
touch "$DEVLOG_DIR/.enabled"

git -C "$TMP_ROOT" init -q -b main
git -C "$TMP_ROOT" config user.email test@example.com
git -C "$TMP_ROOT" config user.name test
echo '.devlog/' > "$TMP_ROOT/.gitignore"
echo one > "$TMP_ROOT/a.txt"
git -C "$TMP_ROOT" add .gitignore a.txt
git -C "$TMP_ROOT" commit -q -m init

FAIL=0
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=1
  fi
}

# write_round: $1 = workspace body, $2 = files body (both may be empty to
# omit the section). Status is always IN_PROGRESS unless $3 overrides it.
write_round() {
  local ws="$1" files="$2" status="${3:-IN_PROGRESS}"
  {
    echo "## Round 1 — 2026-09-11T00:00:00+08:00"
    echo ""
    echo "### Summary"
    echo "fixture"
    echo ""
    echo "### Handoff"
    if [ -n "$files" ]; then
      echo "#### 檔案"
      printf '%s\n' "$files"
    fi
    if [ -n "$ws" ]; then
      echo "#### 工作區"
      printf '%s\n' "$ws"
    fi
    echo "#### 現況"
    echo "fixture"
    if [ "$status" != "DONE" ]; then
      echo "#### 下一步"
      echo "fixture next step"
    fi
    echo ""
    echo "### Status"
    echo "$status"
  } > "$DEVLOG_DIR/devlog.md"
}

ws_clean() {
  local hash
  hash="$(git -C "$TMP_ROOT" rev-parse --short HEAD)"
  echo "main @ ${hash}，工作樹乾淨"
}

# --- committed block, exact match -> allowed ---------------------------------
echo two > "$TMP_ROOT/b.txt"
git -C "$TMP_ROOT" add b.txt
git -C "$TMP_ROOT" commit -q -m "add b"
HASH="$(git -C "$TMP_ROOT" rev-parse --short HEAD)"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "$(ws_clean)" "commit ${HASH}：
新增：b.txt" "DONE"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "commit block matches diff-tree -> allowed" 0 $?

# --- committed block, wrong category -> blocked, message shows expected -----
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "$(ws_clean)" "commit ${HASH}：
修改：b.txt" "DONE"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "commit block wrong category -> blocked" 2 $?
case "$MSG" in
  *"新增：b.txt"*) echo "PASS: message includes the correct category line" ;;
  *) echo "FAIL: message should include '新增：b.txt', got: $MSG"; FAIL=1 ;;
esac

# --- unresolvable commit hash -> fail-open, allowed --------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "$(ws_clean)" "commit 0000000：
新增：nonexistent.txt" "DONE"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unresolvable commit hash -> fail-open, allowed" 0 $?

# --- 尚未 commit, claimed path really dirty -> allowed ------------------------
echo change >> "$TMP_ROOT/a.txt"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}
未提交：a.txt" "尚未 commit：
修改：a.txt" "IN_PROGRESS"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "uncommitted claim matches actual dirty file -> allowed" 0 $?

# --- 尚未 commit, fabricated path -> blocked ----------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}
未提交：a.txt" "尚未 commit：
修改：nope.txt" "IN_PROGRESS"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "uncommitted claim on a path that isn't dirty -> blocked" 2 $?
case "$MSG" in
  *"nope.txt"*) echo "PASS: message names the fabricated path" ;;
  *) echo "FAIL: message should name nope.txt, got: $MSG"; FAIL=1 ;;
esac

# --- 尚未 commit, extra unclaimed dirty residue -> still allowed (one-directional) --
echo untouched-by-this-round > "$TMP_ROOT/residue.txt"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}
未提交：a.txt, residue.txt" "尚未 commit：
修改：a.txt" "IN_PROGRESS"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unclaimed extra dirty file (residue) -> still allowed" 0 $?
rm -f "$TMP_ROOT/residue.txt"
git -C "$TMP_ROOT" checkout -q -- a.txt

# --- malformed 檔案 body -> blocked, format-violation message ------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "$(ws_clean)" "新增了一些東西，忘了寫成規定格式" "DONE"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "unparseable 檔案 body -> blocked" 2 $?
case "$MSG" in
  *"格式不對"*) echo "PASS: message explains the format violation" ;;
  *) echo "FAIL: message should explain the format violation, got: $MSG"; FAIL=1 ;;
esac

# --- empty 檔案 section -> unaffected (existing 瑣碎輪 DONE case) ----------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "" "" "DONE"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "empty 檔案 section -> unaffected, allowed" 0 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
