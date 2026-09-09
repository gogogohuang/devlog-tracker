#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/redact-prompt.sh"
FAIL=0
check() {
  local d="$1" in="$2" needle="$3" forbidden="$4"
  out="$(printf '%s' "$in" | redact_prompt)"
  case "$out" in *"$needle"*) echo "PASS: $d masked" ;; *) echo "FAIL: $d no mask [$out]"; FAIL=1 ;; esac
  if [ -n "$forbidden" ]; then
    case "$out" in *"$forbidden"*) echo "FAIL: $d leaked"; FAIL=1 ;; *) echo "PASS: $d no leak" ;; esac
  fi
}
check ant "token sk-ant-api03-ABCDEFG123456 end" "（已遮罩）" "sk-ant-api03-ABCDEFG123456"
check ghp "ghp_abcdefghijklmnopqrstuvwxyz0123456789" "（已遮罩）" "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
check akia "AKIAIOSFODNN7EXAMPLE" "（已遮罩）" "AKIAIOSFODNN7EXAMPLE"
keep="$(printf '%s' 'see https://example.com/user/alpha' | redact_prompt)"
[ "$keep" = "see https://example.com/user/alpha" ] && echo "PASS: url kept" || { echo "FAIL: url $keep"; FAIL=1; }
pem="$(printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'MIIB' '-----END PRIVATE KEY-----' | redact_prompt)"
case "$pem" in *PRIVATE\ KEY*) echo "FAIL: pem leaked"; FAIL=1 ;; *"（已遮罩）"*) echo "PASS: pem masked" ;; *) echo "FAIL: pem [$pem]"; FAIL=1 ;; esac
if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
