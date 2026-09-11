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

# --- fenced example reordering subsection headings -> ignored, allowed -----
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 決策
說明格式時可以貼一段範例：
\`\`\`markdown
#### 現況
c
#### 決策
d
\`\`\`
真正決定
#### 現況
c"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "fenced example reordering subsection headings -> ignored, allowed" 0 $?

# --- fenced example duplicating a heading already used -> ignored, allowed -
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 決策
真正決策
說明格式時再貼一次範例：
\`\`\`markdown
#### 決策
d2
\`\`\`
#### 現況
c"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "fenced example duplicating a used heading -> ignored, allowed" 0 $?

# --- unterminated fence inside #### 決策 -> fail-open, not a false block
# (final-review Fix 1). A ``` fence that never closes (odd fence-marker
# count) must never make a present #### 現況 register as missing/malformed.
# Status DONE so 下一步/工作區 (Phase 1) stay out of the picture — this only
# exercises section_body()/ORDER_ERR's own fence handling.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 決策
一段沒收尾的範例：
\`\`\`markdown
沒收尾內容，一路吃到 Handoff 結尾
#### 現況
c"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "unterminated fence in 決策, real 現況 after it -> fail-open, allowed" 0 $?

# --- same unterminated fence, but hiding a real duplicate below it --------
# ORDER_ERR re-scans the extracted Handoff body with its own fence tracking;
# pre-fix the same stuck-fence bug hid every #### heading after the broken
# fence from ORDER_ERR too — including a genuine duplicate "#### 決策" that
# should be rejected. NOFENCE degrades ORDER_ERR back to a plain scan for
# this round, so the duplicate check reaches it again. (This is the mirror
# image of the false-block case above: here the pre-fix bug wrongly *allowed*
# something; the point is the same root cause, fixed the same way.)
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
write_round "#### 決策
一段沒收尾的範例：
\`\`\`markdown
沒收尾內容
#### 現況
c
#### 決策
d2（應該被判定為重複）"
MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "unterminated fence no longer hides a real duplicate -> blocked" 2 $?
case "$MSG" in
  *"出現超過一次"*) echo "PASS: duplicate-subsection message despite unterminated fence" ;;
  *) echo "FAIL: expected 出現超過一次 message, got: $MSG"; FAIL=1 ;;
esac

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
