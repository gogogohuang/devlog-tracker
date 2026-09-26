#!/usr/bin/env bash
# Self-check for enforce-devlog.sh's <workspace> machine-verify (Phase 1,
# docs/design/devlog-as-ssot-assessment.md). Separate file from
# test-enforce-devlog.sh to avoid growing that suite further; still
# auto-discovered by run-tests.sh's tests/test-*.sh glob.
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
git -C "$TMP_ROOT" add .gitignore
git -C "$TMP_ROOT" commit -q -m init
HASH="$(git -C "$TMP_ROOT" rev-parse --short HEAD)"

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

write_round() {
  # $1 = workspace body (multi-line ok); empty string omits the section.
  # Writes into .round-current.md — the file enforce-devlog.sh now validates
  # (round-start.sh already opened a skeleton there; this overwrites it).
  local ws="$1"
  {
    echo "## Round 1 — 2026-09-10T00:00:00+08:00"
    echo ""
    echo "### Summary"
    echo "fixture"
    echo ""
    echo "### Reply"
    echo "fixture reply."
    echo ""
    echo "### Handoff"
    if [ -n "$ws" ]; then
      echo "#### 工作區"
      printf '%s\n' "$ws"
    fi
    echo "#### 現況"
    echo "fixture"
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
    echo ""
    echo "### Status"
    echo "IN_PROGRESS"
  } > "$DEVLOG_DIR/.round-current.md"
xml_fixture "$DEVLOG_DIR/.round-current.md"
}

# --- exact match -> allowed --------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}，工作樹乾淨"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "workspace matches live clean git state -> allowed" 0 $?
assert_round_merged "workspace matches live clean git state"

# --- missing section -> blocked, message shows exact expected text ----------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round ""
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "workspace section missing on IN_PROGRESS -> blocked" 2 $?
case "$MSG" in
  *"跟目前 git 狀態不符"*) echo "PASS: message explains the mismatch" ;;
  *) echo "FAIL: message should explain the mismatch, got: $MSG"; FAIL=1 ;;
esac
case "$MSG" in
  *"main @ ${HASH}，工作樹乾淨"*) echo "PASS: message includes the exact expected snapshot" ;;
  *) echo "FAIL: message should include the exact expected snapshot, got: $MSG"; FAIL=1 ;;
esac

# --- stale hash -> blocked ---------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ 0000000，工作樹乾淨"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "workspace with stale hash -> blocked" 2 $?

# --- dirty tree, exact two-line match -> allowed -----------------------------
echo change >> "$TMP_ROOT/a.txt"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}
未提交：a.txt"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "dirty tree, exact two-line workspace -> allowed" 0 $?
assert_round_merged "dirty tree, exact two-line workspace"
git -C "$TMP_ROOT" checkout -q -- a.txt 2>/dev/null || rm -f "$TMP_ROOT/a.txt"

# --- BLOCKED status is also enforced -----------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 2 — 2026-09-10T00:05:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Reply"
  echo "fixture reply."
  echo ""
  echo "### Handoff"
  echo "#### 現況"
  echo "缺使用者提供的 token（出現即繼續）"
  echo "#### 完成條件"
  echo "缺件已到且可觀察條件達成。"
  echo "#### 下一步"
  echo "等使用者提供 token 後接著改 hooks/foo.sh"
  echo ""
  echo "### Status"
  echo "BLOCKED"
} > "$DEVLOG_DIR/.round-current.md"
xml_fixture "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "BLOCKED with missing workspace -> blocked" 2 $?

# --- DONE is unaffected (check only applies to IN_PROGRESS/BLOCKED) ---------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 3 — 2026-09-10T00:10:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Reply"
  echo "fixture reply."
  echo ""
  echo "### Handoff"
  echo "#### 現況"
  echo "fixture"
  echo ""
  echo "### Status"
  echo "DONE"
} > "$DEVLOG_DIR/.round-current.md"
xml_fixture "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "DONE with no workspace section -> allowed (check does not apply)" 0 $?
assert_round_merged "DONE with no workspace section"

# --- fenced example quoting a legacy `#### 工作區` inside <decisions> before
# the real <workspace> -> the quoted text stays plain content of <decisions>
# after xml_fixture, and the workspace check still reads the real <workspace>
# body -------------------------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 4 — 2026-09-10T00:15:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Reply"
  echo "fixture reply."
  echo ""
  echo "### Handoff"
  echo "#### 決策"
  echo "範例格式："
  echo '```markdown'
  echo "#### 工作區"
  echo "main @ 0000000，工作樹乾淨"
  echo '```'
  echo "真正決策內容"
  echo "#### 工作區"
  echo "main @ ${HASH}，工作樹乾淨"
  echo "#### 現況"
  echo "fixture"
  echo "#### 完成條件"
  echo "observable done via test."
  echo "#### 下一步"
  echo "edit hooks/scripts/enforce-devlog.sh"
  echo ""
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
  echo ""
  echo "### Status"
  echo "IN_PROGRESS"
} > "$DEVLOG_DIR/.round-current.md"
xml_fixture "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "fenced example quoting #### 工作區 before the real section -> allowed" 0 $?
assert_round_merged "fenced example quoting #### 工作區 before the real section"

# --- unterminated fence in an earlier field -> not a false block. A ```
# fence that never closes must never make a present, filled-in <next>
# register as missing: XML fields don't track fences at all. Written as XML
# directly — the legacy converter leaves odd-fence rounds untouched.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 5 — 2026-09-10T00:20:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Reply"
  echo "fixture reply."
  echo ""
  echo "### Handoff"
  echo "<handoff>"
  echo "<workspace>"
  echo "main @ ${HASH}，工作樹乾淨"
  echo "</workspace>"
  echo "<state>"
  echo "一段沒收尾的範例："
  echo '```markdown'
  echo "沒收尾內容，一路吃到這個 Round 結尾"
  echo "</state>"
  echo "<done-when>"
  echo "observable done via test."
  echo "</done-when>"
  echo "<next>"
  echo "edit hooks/scripts/enforce-devlog.sh"
  echo "</next>"
  echo "</handoff>"
  echo ""
  echo ""
  echo "### Session Handoff"
  echo "<session-handoff>"
  echo "<decisions>"
  echo "- （無）"
  echo "</decisions>"
  echo "<open-questions>"
  echo "- fixture open"
  echo "</open-questions>"
  echo "<failed-attempts>"
  echo "- （無）"
  echo "</failed-attempts>"
  echo "</session-handoff>"
  echo ""
  echo "### Status"
  echo "IN_PROGRESS"
} > "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unterminated fence in 現況 -> fail-open, 下一步 still recognized" 0 $?
assert_round_merged "unterminated fence in 現況"

# --- DONE with a non-empty <files> (claims files were touched/committed)
# IS now checked: a DONE round that reports file changes but has no/wrong
# <workspace> is exactly the "已 commit 完成" false-claim case
# devlog-as-ssot-assessment.md flags as uncaught — machine-verify it the
# same way IN_PROGRESS/BLOCKED already are. A trivial DONE round with no
# <files> stays exempt (previous test above), matching SKILL.md's
# "瑣碎輪只留現況一句（沒有工作區）" convention untouched.
#
# The <files> body below is just "尚未 commit：" with no claimed paths —
# this suite only cares about triggering the <workspace> check via a non-empty
# <files>, not about <files> content itself (that's
# test-enforce-devlog-files.sh's job, Phase 4). Any grammar-valid,
# always-passing body works here. ------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 6 — 2026-09-10T00:25:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Reply"
  echo "fixture reply."
  echo ""
  echo "### Handoff"
  echo "#### 檔案"
  echo "尚未 commit："
  echo "#### 現況"
  echo "fixture"
  echo ""
  echo "### Status"
  echo "DONE"
} > "$DEVLOG_DIR/.round-current.md"
xml_fixture "$DEVLOG_DIR/.round-current.md"
MSG_DONE="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "DONE with #### 檔案 but no #### 工作區 -> blocked" 2 $?
case "$MSG_DONE" in
  *"main @ ${HASH}，工作樹乾淨"*) echo "PASS: DONE block message includes exact expected snapshot" ;;
  *) echo "FAIL: DONE block message should include exact expected snapshot, got: $MSG_DONE"; FAIL=1 ;;
esac

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 6 — 2026-09-10T00:25:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Reply"
  echo "fixture reply."
  echo ""
  echo "### Handoff"
  echo "#### 檔案"
  echo "尚未 commit："
  echo "#### 工作區"
  echo "main @ 0000000，工作樹乾淨"
  echo "#### 現況"
  echo "fixture"
  echo ""
  echo "### Status"
  echo "DONE"
} > "$DEVLOG_DIR/.round-current.md"
xml_fixture "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "DONE with #### 檔案 and stale 工作區 hash -> blocked" 2 $?

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 6 — 2026-09-10T00:25:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Reply"
  echo "fixture reply."
  echo ""
  echo "### Handoff"
  echo "#### 檔案"
  echo "尚未 commit："
  echo "#### 工作區"
  echo "main @ ${HASH}，工作樹乾淨"
  echo "#### 現況"
  echo "fixture"
  echo ""
  echo "### Status"
  echo "DONE"
} > "$DEVLOG_DIR/.round-current.md"
xml_fixture "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "DONE with #### 檔案 and matching 工作區 -> allowed" 0 $?
assert_round_merged "DONE with #### 檔案 and matching 工作區"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
