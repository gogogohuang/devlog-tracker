#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected [$expected] got [$actual])"; FAIL=1; fi
}

printf '%s\n' '{"ticks_since_checkin": 2, "max_silent_ticks": 5}' > "$TMP"
assert_eq "int get" "2" "$(json_int_get "$TMP" ticks_since_checkin)"
assert_eq "int get max" "5" "$(json_int_get "$TMP" max_silent_ticks)"
assert_eq "missing key" "" "$(json_int_get "$TMP" no_such)"

printf '%s\n' '{"ticks_since_checkin": 08}' > "$TMP"
assert_eq "reject octal pad" "" "$(json_int_get "$TMP" ticks_since_checkin)"

printf '%s\n' '{"opened_at": "2026-09-08T21:40:00+08:00", "round": 12}' > "$TMP"
assert_eq "str get" "2026-09-08T21:40:00+08:00" "$(json_str_get "$TMP" opened_at)"
assert_eq "int round" "12" "$(json_int_get "$TMP" round)"

printf '%s\n' '{"ticks_since_checkin": 2, "max_silent_ticks": 5}' > "$TMP"
json_int_set "$TMP" ticks_since_checkin 0
assert_eq "int set" "0" "$(json_int_get "$TMP" ticks_since_checkin)"
assert_eq "int set preserves sibling" "5" "$(json_int_get "$TMP" max_silent_ticks)"

printf '%s\n' '{"last_seen_cksum": "old", "last_change_epoch": 1}' > "$TMP"
json_str_set "$TMP" last_seen_cksum "123 2"
assert_eq "str set" "123 2" "$(json_str_get "$TMP" last_seen_cksum)"
assert_eq "str set preserves epoch" "1" "$(json_int_get "$TMP" last_change_epoch)"

printf '%s\n' 'not json' > "$TMP"
assert_eq "malformed int" "" "$(json_int_get "$TMP" round)"
assert_eq "malformed str" "" "$(json_str_get "$TMP" opened_at)"

INPUT='{"session_id": "abc-123", "prompt": "hello world"}'
assert_eq "str field get" "abc-123" "$(json_str_field "$INPUT" session_id)"
assert_eq "str field get other key" "hello world" "$(json_str_field "$INPUT" prompt)"
assert_eq "str field missing key" "" "$(json_str_field "$INPUT" no_such)"

INPUT='{"reason": null}'
assert_eq "str field null" "" "$(json_str_field "$INPUT" reason)"

INPUT='not json'
assert_eq "str field malformed" "" "$(json_str_field "$INPUT" reason)"

# Escaped characters must survive with and without jq (the no-jq path is a
# grep/awk fallback). NOJQ_BIN is a PATH holding only the tools the fallback
# needs, so `command -v jq` fails inside it.
NOJQ_BIN="$(mktemp -d)"
trap 'rm -f "$TMP"; rm -rf "$NOJQ_BIN"' EXIT
for b in grep sed awk head tr cat; do
  for d in /usr/bin /bin; do [ -x "$d/$b" ] && { ln -s "$d/$b" "$NOJQ_BIN/$b"; break; }; done
done
INPUT='{"session_id":"s","prompt":"say \"hi\" \\ back\/slash\ttab 你好","after":"ok"}'
EXPECT_PROMPT="$(printf 'say "hi" \\ back/slash\ttab 你好')"
for mode in jq nojq; do
  if [ "$mode" = nojq ]; then P="$NOJQ_BIN"; else P="$PATH"; fi
  [ "$mode" = jq ] && ! command -v jq >/dev/null 2>&1 && continue
  assert_eq "[$mode] escaped quote/backslash/tab prompt" "$EXPECT_PROMPT" "$(PATH="$P" json_str_field "$INPUT" prompt)"
  assert_eq "[$mode] field after escaped one" "ok" "$(PATH="$P" json_str_field "$INPUT" after)"
done

assert_eq "slugify basic" "foo-bar" "$(slugify 'foo bar')"
assert_eq "slugify collapses runs" "foo-bar" "$(slugify 'foo   bar')"
assert_eq "slugify trims edges" "foo" "$(slugify ' foo ')"

assert_eq "json_escape quotes and backslash" 'a \"q\" \\ b' "$(json_escape 'a "q" \ b')"
assert_eq "json_escape tab" 'x\ty' "$(json_escape "$(printf 'x\ty')")"
assert_eq "json_escape newline" 'l1\nl2' "$(json_escape "$(printf 'l1\nl2')")"
assert_eq "json_escape CJK passthrough" '中文' "$(json_escape '中文')"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
