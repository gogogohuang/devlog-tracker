#!/usr/bin/env bash
# Self-check for enforce-devlog.sh's <files> machine-verify (Phase 4,
# docs/design/files-verify.md). Separate file from test-enforce-devlog.sh
# and test-enforce-devlog-workspace.sh; still auto-discovered by
# run-tests.sh's tests/test-*.sh glob.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/xml-fixture.sh
. "$SCRIPT_DIR/tests/lib/xml-fixture.sh"
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

# Round-current split: enforce-devlog.sh validates .round-current.md now
# (not devlog.md), and merges it into devlog.md on success. One assertion
# per "should succeed" case exercises that merge.
assert_round_merged() {
  local desc="$1" marker="${2:-fixture}"
  if [ -f "$DEVLOG_DIR/.round-current.md" ]; then
    echo "FAIL: $desc (.round-current.md should be merged away)"
    FAIL=1
  elif ! grep -q "$marker" "$DEVLOG_DIR/devlog.md" 2>/dev/null; then
    echo "FAIL: $desc (devlog.md missing merged content)"
    FAIL=1
  else
    echo "PASS: $desc (round-current merged into devlog.md)"
  fi
}

# write_round: $1 = workspace body, $2 = files body (both may be empty to
# omit the section). Status is always IN_PROGRESS unless $3 overrides it.
# Writes into .round-current.md — the file enforce-devlog.sh now validates
# (round-start.sh already opened a skeleton there; this overwrites it).
write_round() {
  local ws="$1" files="$2" status="${3:-IN_PROGRESS}"
  {
    echo "## Round 1 — 2026-09-11T00:00:00+08:00"
    echo ""
    echo "### Summary"
    echo "fixture"
    echo ""
    echo "### Reply"
    echo "fixture reply."
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
      echo "#### 完成條件"
      echo "observable done via test."
      echo "#### 下一步"
      echo "edit hooks/scripts/enforce-devlog.sh"
      echo ""
      echo "### Session Handoff"
      echo ""
      echo "#### 決策"
      echo "- （無）"
      echo ""
      echo "#### 待解問題"
      echo "- fixture open"
      echo ""
      echo "#### 失敗嘗試"
      echo "- （無）"
    fi
    echo ""
    echo "### Status"
    echo "$status"
  } > "$DEVLOG_DIR/.round-current.md"
  xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
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
assert_round_merged "commit block matches diff-tree"

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
assert_round_merged "unresolvable commit hash"

# --- 尚未 commit, claimed path really dirty -> allowed ------------------------
echo change >> "$TMP_ROOT/a.txt"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}
未提交：a.txt" "尚未 commit：
修改：a.txt" "IN_PROGRESS"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "uncommitted claim matches actual dirty file -> allowed" 0 $?
assert_round_merged "uncommitted claim matches actual dirty file"

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
assert_round_merged "unclaimed extra dirty file (residue)"
rm -f "$TMP_ROOT/residue.txt"
git -C "$TMP_ROOT" checkout -q -- a.txt

# --- 尚未 commit, fabricated path against a genuinely clean tree -> blocked, not
# a crash. Regression for Finding 1: path_in_list used to build a bash array
# via `IFS=',' read -ra arr <<< "$haystack"`; on bash 3.2 (this suite's floor)
# an empty haystack (clean tree) makes that a genuinely empty array, and
# "${arr[@]}" on it is an unbound-variable error under `set -uo pipefail` —
# the script died with exit 1 and a raw traceback instead of the intended
# exit 2 block. A clean tree is exactly when ACTUAL_JOINED is empty, so this
# is also the headline case the feature exists to catch (a false "still
# uncommitted" claim).
git -C "$TMP_ROOT" status --short --no-renames | grep -q . && {
  echo "FIXTURE BUG: tree should be clean before the Finding-1 regression test" >&2
  FAIL=1
}
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "$(ws_clean)" "尚未 commit：
修改：ghost.txt" "DONE"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "uncommitted claim against a clean tree -> blocked, not a crash" 2 $?
case "$MSG" in
  *"ghost.txt"*) echo "PASS: message names the fabricated path" ;;
  *) echo "FAIL: message should name ghost.txt, got: $MSG"; FAIL=1 ;;
esac
case "$MSG" in
  *"工作樹乾淨"*) echo "PASS: message shows the actual-dirty fallback text" ;;
  *) echo "FAIL: message should show the clean-tree fallback text, got: $MSG"; FAIL=1 ;;
esac

# --- commit resolves but its outside-.devlog/ diff is empty -> must still be
# compared (not silently fail-open); a fabricated claim against it is blocked.
# Regression for Finding 2: files_snapshot returns empty stdout both when a
# hash doesn't resolve and when it resolves but has nothing to report outside
# .devlog/ — check_commit_block must tell these apart via its own rev-parse,
# not infer "unresolvable" from empty output. Placed after every test above
# that hardcodes `$HASH` against the current HEAD, since this test advances
# HEAD with a new commit.
echo devlog-only-change > "$TMP_ROOT/.devlog/marker.txt"
git -C "$TMP_ROOT" add -f .devlog/marker.txt
git -C "$TMP_ROOT" commit -q -m "devlog-only change"
DEVLOG_ONLY_HASH="$(git -C "$TMP_ROOT" rev-parse --short HEAD)"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "$(ws_clean)" "commit ${DEVLOG_ONLY_HASH}：
新增：fabricated.ts" "DONE"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "commit with empty outside-.devlog diff + fabricated claim -> blocked" 2 $?
case "$MSG" in
  *"跟宣稱不符"*) echo "PASS: message reports the mismatch instead of silently passing" ;;
  *) echo "FAIL: message should report a mismatch, got: $MSG"; FAIL=1 ;;
esac

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
assert_round_merged "empty 檔案 section"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
