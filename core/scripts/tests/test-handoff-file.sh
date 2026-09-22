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
#### 現況
c
#### 完成條件
done when tests pass
#### 下一步
edit core/scripts/handoff-file.sh

### Session Handoff

#### 決策
- pick route A

#### 待解問題
- （無）

#### 失敗嘗試
- tried parse-in-place

### Status
IN_PROGRESS
'

BAD_ORDER='### Session Handoff
#### 待解問題
- x
#### 決策
- y
#### 失敗嘗試
- z
'

MISSING='### Session Handoff
#### 決策
- x
#### 失敗嘗試
- z
'

if handoff_session_section_ok "$GOOD_ROUND"; then
  echo "PASS: good round validates"
else
  echo "FAIL: good round should validate"; FAIL=1
fi

if handoff_session_section_ok "$BAD_ORDER"; then
  echo "FAIL: bad order should fail"; FAIL=1
else
  echo "PASS: bad order rejected"
fi

if handoff_session_section_ok "$MISSING"; then
  echo "FAIL: missing 待解問題 should fail"; FAIL=1
else
  echo "PASS: missing subsection rejected"
fi

OUT="$(handoff_extract_file_body "$GOOD_ROUND")" || { echo "FAIL: extract exited $?"; FAIL=1; OUT=""; }
if printf '%s\n' "$OUT" | grep -q '^## Session Handoff' \
  && printf '%s\n' "$OUT" | grep -q '^### 決策' \
  && printf '%s\n' "$OUT" | grep -q 'pick route A' \
  && printf '%s\n' "$OUT" | grep -q '^### 待解問題' \
  && printf '%s\n' "$OUT" | grep -q '（無）' \
  && printf '%s\n' "$OUT" | grep -q '^### 失敗嘗試' \
  && printf '%s\n' "$OUT" | grep -q 'tried parse-in-place'; then
  echo "PASS: extract shape"
else
  echo "FAIL: extract shape, got: $OUT"; FAIL=1
fi

TARGET="$TMP/handoff.md"
handoff_write "$TARGET" "$GOOD_ROUND" || { echo "FAIL: write"; FAIL=1; }
[ -s "$TARGET" ] && grep -q 'pick route A' "$TARGET" \
  && echo "PASS: write creates file" \
  || { echo "FAIL: write"; FAIL=1; }

handoff_clear "$TARGET"
[ ! -f "$TARGET" ] && echo "PASS: clear removes file" \
  || { echo "FAIL: clear left file"; FAIL=1; }

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
