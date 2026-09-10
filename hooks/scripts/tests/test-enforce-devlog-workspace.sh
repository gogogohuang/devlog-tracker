#!/usr/bin/env bash
# Self-check for enforce-devlog.sh's #### 工作區 machine-verify (Phase 1,
# docs/design/devlog-as-ssot-assessment.md). Separate file from
# test-enforce-devlog.sh to avoid growing that suite further; still
# auto-discovered by run-tests.sh's tests/test-*.sh glob.
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

write_round() {
  # $1 = workspace body (multi-line ok); empty string omits the section.
  local ws="$1"
  {
    echo "## Round 1 — 2026-09-10T00:00:00+08:00"
    echo ""
    echo "### Summary"
    echo "fixture"
    echo ""
    echo "### Handoff"
    echo "#### 現況"
    echo "fixture"
    if [ -n "$ws" ]; then
      echo "#### 工作區"
      printf '%s\n' "$ws"
    fi
    echo "#### 下一步"
    echo "fixture next step"
    echo ""
    echo "### Status"
    echo "IN_PROGRESS"
  } > "$DEVLOG_DIR/devlog.md"
}

# --- exact match -> allowed --------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "main @ ${HASH}，工作樹乾淨"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "workspace matches live clean git state -> allowed" 0 $?

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
git -C "$TMP_ROOT" checkout -q -- a.txt 2>/dev/null || rm -f "$TMP_ROOT/a.txt"

# --- BLOCKED status is also enforced -----------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
{
  echo "## Round 2 — 2026-09-10T00:05:00+08:00"
  echo ""
  echo "### Summary"
  echo "fixture"
  echo ""
  echo "### Handoff"
  echo "#### 現況"
  echo "fixture"
  echo "#### 下一步"
  echo "fixture next step"
  echo ""
  echo "### Status"
  echo "BLOCKED"
} > "$DEVLOG_DIR/devlog.md"
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
  echo "### Handoff"
  echo "#### 現況"
  echo "fixture"
  echo ""
  echo "### Status"
  echo "DONE"
} > "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "DONE with no workspace section -> allowed (check does not apply)" 0 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
