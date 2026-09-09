#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

assert_eq "slugify basic" "foo-bar" "$(slugify 'foo bar')"
assert_eq "slugify collapses runs" "foo-bar" "$(slugify 'foo   bar')"
assert_eq "slugify trims edges" "foo" "$(slugify ' foo ')"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
