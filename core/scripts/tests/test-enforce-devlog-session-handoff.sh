#!/usr/bin/env bash
# Self-check for Session Handoff enforce + handoff.md sync.
# docs/design/session-handoff-file.md
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

SESSION_OK='
### Session Handoff

#### 決策
- pick route A

#### 待解問題
- still wiring enforce

#### 失敗嘗試
- （無）
'

write_unfinished() {
  local status="$1" session="$2"
  {
    echo "## Round 1 — 2026-09-22T00:00:00+08:00"
    echo ""
    echo "### Summary"
    echo "fixture"
    echo ""
    echo "### Reply"
    echo "fixture reply."
    echo ""
    echo "### Handoff"
    echo "#### 工作區"
    echo "main @ ${HASH}，工作樹乾淨"
    echo "#### 現況"
    if [ "$status" = "BLOCKED" ]; then
      echo "缺使用者提供的 token（出現即繼續）"
    else
      echo "fixture"
    fi
    echo "#### 完成條件"
    echo "observable done via test."
    echo "#### 下一步"
    if [ "$status" = "BLOCKED" ]; then
      echo "等使用者提供 token 後改 hooks/foo.sh"
    else
      echo "edit core/scripts/enforce-devlog.sh"
    fi
    if [ -n "$session" ]; then
      printf '%s\n' "$session"
    fi
    echo ""
    echo "### Status"
    echo "$status"
  } > "$DEVLOG_DIR/.round-current.md"
  xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
}

# 1) IN_PROGRESS without Session Handoff -> blocked
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_unfinished IN_PROGRESS ""
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "IN_PROGRESS without Session Handoff -> blocked" 2 $?
case "$MSG" in
  *"Session Handoff"*) echo "PASS: message mentions Session Handoff" ;;
  *) echo "FAIL: expected Session Handoff in message, got: $MSG"; FAIL=1 ;;
esac

# 2) IN_PROGRESS with Session Handoff -> write handoff.md
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_unfinished IN_PROGRESS "$SESSION_OK"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "IN_PROGRESS with Session Handoff -> allowed" 0 $?
if [ -f "$DEVLOG_DIR/handoff.md" ] && grep -q 'pick route A' "$DEVLOG_DIR/handoff.md" \
  && grep -q '^## Session Handoff' "$DEVLOG_DIR/handoff.md"; then
  echo "PASS: handoff.md written from Session Handoff"
else
  echo "FAIL: handoff.md missing or wrong"; FAIL=1
fi

# 3) BLOCKED with Session Handoff -> updates file
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_unfinished BLOCKED "
### Session Handoff

#### 決策
- （無）

#### 待解問題
- waiting on token

#### 失敗嘗試
- （無）
"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "BLOCKED with Session Handoff -> allowed" 0 $?
if grep -q 'waiting on token' "$DEVLOG_DIR/handoff.md" 2>/dev/null; then
  echo "PASS: handoff.md updated on BLOCKED"
else
  echo "FAIL: handoff.md not updated on BLOCKED"; FAIL=1
fi

# 4) DONE clears handoff.md
echo "stale" > "$DEVLOG_DIR/handoff.md"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 1 — 2026-09-22T01:00:00+08:00"
  echo ""
  echo "### Summary"
  echo "done"
  echo ""
  echo "### Reply"
  echo "done reply."
  echo ""
  echo "### Handoff"
  echo "#### 現況"
  echo "finished"
  echo ""
  echo "### Status"
  echo "DONE"
} > "$DEVLOG_DIR/.round-current.md"
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "DONE -> allowed" 0 $?
if [ ! -f "$DEVLOG_DIR/handoff.md" ]; then
  echo "PASS: DONE deletes handoff.md"
else
  echo "FAIL: handoff.md survived DONE"; FAIL=1
fi

# 5) wrong order -> blocked; existing handoff unchanged
echo "keep-me" > "$DEVLOG_DIR/handoff.md"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_unfinished IN_PROGRESS "
### Session Handoff

#### 待解問題
- x

#### 決策
- y

#### 失敗嘗試
- z
"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "wrong Session Handoff order -> blocked" 2 $?
if [ -f "$DEVLOG_DIR/handoff.md" ] && grep -q 'keep-me' "$DEVLOG_DIR/handoff.md"; then
  echo "PASS: handoff.md unchanged on validation failure"
else
  echo "FAIL: handoff.md should be untouched on validation failure"; FAIL=1
fi

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
