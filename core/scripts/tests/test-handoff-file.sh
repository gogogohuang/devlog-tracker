#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../handoff-file.sh
. "$SCRIPT_DIR/handoff-file.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

GOOD_ROUND='## Round 1 — 2026-09-22T00:00:00+08:00

### Summary
s

### Reply
r

### Handoff
<handoff>
<state>
c
</state>
<done-when>
done when tests pass
</done-when>
<next>
edit core/scripts/handoff-file.sh
</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- pick route A
</decisions>
<open-questions>
- （無）
</open-questions>
<failed-attempts>
- tried parse-in-place
</failed-attempts>
</session-handoff>

### Status
IN_PROGRESS
'

EXPECTED='<session-handoff>
<decisions>
- pick route A
</decisions>
<open-questions>
- （無）
</open-questions>
<failed-attempts>
- tried parse-in-place
</failed-attempts>
</session-handoff>'

BAD_ORDER='### Session Handoff
<session-handoff>
<open-questions>
- x
</open-questions>
<decisions>
- y
</decisions>
<failed-attempts>
- z
</failed-attempts>
</session-handoff>
'

MISSING='### Session Handoff
<session-handoff>
<decisions>
- x
</decisions>
</session-handoff>
'

LEGACY='### Session Handoff
#### 決策
- x
#### 待解問題
- y
#### 失敗嘗試
- z
'

TARGET="$TMP/handoff.md"
if handoff_write "$TARGET" "$GOOD_ROUND"; then
  if [ "$(cat "$TARGET")" = "$EXPECTED" ]; then
    echo "PASS: write stores <session-handoff> block verbatim"
  else
    echo "FAIL: handoff.md content, got:"; cat "$TARGET"; FAIL=1
  fi
else
  echo "FAIL: write good round returned non-zero"; FAIL=1
fi

expect_rejected() {
  local name="$1" blob="$2" bad_target="$TMP/bad-$1.md"
  if handoff_write "$bad_target" "$blob"; then
    echo "FAIL: $name should be rejected"; FAIL=1
  elif [ -e "$bad_target" ]; then
    echo "FAIL: $name left a file behind"; FAIL=1
  else
    echo "PASS: $name rejected, no file written"
  fi
}
expect_rejected BAD_ORDER "$BAD_ORDER"
expect_rejected MISSING "$MISSING"
expect_rejected LEGACY "$LEGACY"

handoff_clear "$TARGET"
[ ! -f "$TARGET" ] && echo "PASS: clear removes file" \
  || { echo "FAIL: clear left file"; FAIL=1; }

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
