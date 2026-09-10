#!/usr/bin/env bash
# Self-check for enforce-devlog.sh's Handoff subsection order/duplicate
# check (Phase 2, docs/design/devlog-as-ssot-assessment.md). No framework —
# plain assert-and-exit, matching this repo's existing style.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"
touch "$DEVLOG_DIR/.enabled"

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
  # $1 = Handoff body (already includes #### subsection lines). Status DONE
  # throughout so this suite is decoupled from Phase 1's 工作區/下一步 checks.
  {
    echo "## Round 1 — 2026-09-10T00:00:00+08:00"
    echo ""
    echo "### Summary"
    echo "fixture"
    echo ""
    echo "### Handoff"
    printf '%s\n' "$1"
    echo ""
    echo "### Status"
    echo "DONE"
  } > "$DEVLOG_DIR/devlog.md"
}

# --- full canonical order -> allowed -----------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 決策
d
#### 檔案
f
#### 工作區
main @ abc123，工作樹乾淨
#### 現況
c
#### 下一步
n"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "full canonical order -> allowed" 0 $?

# --- subset in order -> allowed -----------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 決策
d
#### 現況
c"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "subset in canonical order -> allowed" 0 $?

# --- reordered -> blocked -------------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 現況
c
#### 決策
d"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "現況 before 決策 -> blocked" 2 $?
case "$MSG" in
  *"順序錯了"*) echo "PASS: order-violation message" ;;
  *) echo "FAIL: expected 順序錯了 message, got: $MSG"; FAIL=1 ;;
esac

# --- duplicate -> blocked -------------------------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 現況
c1
#### 現況
c2"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "duplicate 現況 -> blocked" 2 $?
case "$MSG" in
  *"出現超過一次"*) echo "PASS: duplicate-subsection message" ;;
  *) echo "FAIL: expected 出現超過一次 message, got: $MSG"; FAIL=1 ;;
esac

# --- unrecognized heading interleaved -> ignored, allowed ------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 決策
d
#### 其他備註
x
#### 現況
c"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unrecognized #### heading interleaved -> ignored, allowed" 0 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
