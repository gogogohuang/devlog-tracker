#!/usr/bin/env bash
# Self-check for enforce-devlog.sh's Handoff format gate: XML tag order／
# duplicate／unknown-tag checks and legacy-format blocking
# (docs/design/handoff-xml.md). No framework —
# plain assert-and-exit, matching this repo's existing style.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"
touch "$DEVLOG_DIR/.enabled"

# A real (if minimal) git repo, only so the "full canonical order" fixture's
# <files> + <workspace> pair below can carry a <workspace> that actually
# matches live git — DONE rounds with a non-empty <files> are
# machine-verified too. Every other fixture in this file keeps Status DONE
# with no <files>, so it stays decoupled from this check.
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
  # $1 = Handoff body (already includes the <handoff> block). Status DONE
  # throughout so this suite is decoupled from Phase 1's 工作區/下一步 checks.
  # Writes into .round-current.md — the file enforce-devlog.sh now validates
  # (round-start.sh already opened a skeleton there; this overwrites it).
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
    printf '%s\n' "$1"
    echo ""
    echo "### Status"
    echo "DONE"
  } > "$DEVLOG_DIR/.round-current.md"
}

# --- full canonical order -> allowed -----------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<decisions>
d
</decisions>
<files>
尚未 commit：
</files>
<workspace>
main @ ${HASH}，工作樹乾淨
</workspace>
<state>
c
</state>
<done-when>
observable done.
</done-when>
<next>
n
</next>
</handoff>"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "full canonical order -> allowed" 0 $?
assert_round_merged "full canonical order"

# --- subset in order -> allowed -----------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<decisions>
d
</decisions>
<state>
c
</state>
</handoff>"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "subset in canonical order -> allowed" 0 $?
assert_round_merged "subset in canonical order"

# --- reordered -> blocked -------------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<state>
c
</state>
<decisions>
d
</decisions>
</handoff>"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "state before decisions -> blocked" 2 $?
case "$MSG" in
  *"順序錯了"*) echo "PASS: order-violation message" ;;
  *) echo "FAIL: expected 順序錯了 message, got: $MSG"; FAIL=1 ;;
esac

# --- duplicate -> blocked -------------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<state>
c1
</state>
<state>
c2
</state>
</handoff>"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "duplicate state -> blocked" 2 $?
case "$MSG" in
  *"出現超過一次"*) echo "PASS: duplicate-tag message" ;;
  *) echo "FAIL: expected 出現超過一次 message, got: $MSG"; FAIL=1 ;;
esac

# --- unknown tag -> blocked (spec rule 6: no silently ignored subsections) ---
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<decisions>
d
</decisions>
<notes>
x
</notes>
</handoff>"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "unknown tag -> blocked" 2 $?
case "$MSG" in
  *"不認得的標籤"*) echo "PASS: unknown-tag message" ;;
  *) echo "FAIL: expected 不認得的標籤 message, got: $MSG"; FAIL=1 ;;
esac

# --- fenced legacy example inside a field -> plain content, allowed --------
# XML fields don't track fences; a ``` block quoting old #### headings is
# just text in <decisions>.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<decisions>
說明格式時可以貼一段範例：
\`\`\`markdown
#### 現況
c
#### 決策
d
\`\`\`
真正決定
</decisions>
<state>
c
</state>
</handoff>"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "fenced #### example inside <decisions> -> allowed" 0 $?
assert_round_merged "fenced #### example inside <decisions>"

# --- unterminated fence inside a field -> fail-open, allowed ----------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<decisions>
一段沒收尾的範例：
\`\`\`markdown
沒收尾內容
</decisions>
<state>
c
</state>
</handoff>"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unterminated fence in <decisions> -> allowed" 0 $?
assert_round_merged "unterminated fence in <decisions>"

# --- unterminated fence does not hide a real duplicate tag -------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "<handoff>
<decisions>
一段沒收尾的範例：
\`\`\`markdown
沒收尾內容
</decisions>
<state>
c
</state>
<decisions>
d2（應該被判定為重複）
</decisions>
</handoff>"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "unterminated fence no longer hides a real duplicate -> blocked" 2 $?
case "$MSG" in
  *"出現超過一次"*) echo "PASS: duplicate-tag message despite unterminated fence" ;;
  *) echo "FAIL: expected 出現超過一次 message, got: $MSG"; FAIL=1 ;;
esac

# --- XML gate (docs/design/handoff-xml.md) ---
write_handoff_round() {  # $1 = Handoff body lines (already formatted)
  {
    echo "## Round 1 — 2026-09-26T00:00:00+08:00"
    echo ""
    echo "### Summary"; echo "s"; echo ""
    echo "### Reply"; echo "r"; echo ""
    echo "### Handoff"
    printf '%s\n' "$1"
    echo ""
    echo "### Status"; echo "DONE"
  } > "$DEVLOG_DIR/.round-current.md"
}

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '#### 現況
legacy'
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "legacy Handoff blocked" 2 $?
case "$MSG" in
  *"migrate-handoff.sh"*"<handoff>"*"npx devlog-tracker init"*) echo "PASS: legacy message has migrate, template, init hint" ;;
  *) echo "FAIL: legacy message: $MSG"; FAIL=1 ;;
esac

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '<handoff>
<state>
ok
</state>
</handoff>'
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "XML Handoff DONE passes" 0 $?

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '<handoff>
<next>
x
</next>
<state>
y
</state>
</handoff>'
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "XML order violation blocked" 2 $?
case "$MSG" in *"順序"*"### Handoff"*"<handoff>"*) echo "PASS: order message + template" ;; *) echo "FAIL: order msg: $MSG"; FAIL=1 ;; esac

bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_handoff_round '<handoff>
<state>
y
</state>'
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unclosed handoff blocked" 2 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
