#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

OUT="$(bash "$SCRIPT_DIR/status-devlog.sh")"
[ "$OUT" = "NOT_STARTED" ] && pass "not started" || fail "not started [$OUT]"

mkdir -p "$TMP/.devlog"
touch "$TMP/.devlog/.enabled"
cat > "$TMP/.devlog/devlog.md" <<'EOF'
## Round 1 — now

### Status
DONE
EOF
OUT="$(bash "$SCRIPT_DIR/status-devlog.sh")"
case "$OUT" in *"ENABLED=yes"*) pass "enabled" ;; *) fail "enabled [$OUT]" ;; esac
case "$OUT" in *"SPAN=closed"*) pass "span closed" ;; *) fail "span closed [$OUT]" ;; esac
case "$OUT" in *"LAST_STATUS=DONE"*) pass "last status" ;; *) fail "last status [$OUT]" ;; esac

OUT="$(bash "$SCRIPT_DIR/span-open.sh")"
[ "$OUT" = "OPENED=1" ] && pass "span opened" || fail "span open [$OUT]"
grep -q '"round": 1' "$TMP/.devlog/.span-open" && pass "round stored" || fail "round stored"
grep -q '"ticks_since_checkin": 0' "$TMP/.devlog/.span-open" && pass "ticks default" || fail "ticks default"
grep -q '"max_silent_ticks": 5' "$TMP/.devlog/.span-open" && pass "max default" || fail "max default"
bash "$SCRIPT_DIR/span-open.sh" >/dev/null 2>&1
[ "$?" -eq 1 ] && pass "second open rejected" || fail "second open"
OUT="$(bash "$SCRIPT_DIR/span-close.sh")"
[ "$OUT" = "CLOSED" ] && pass "span closed output" || fail "close output [$OUT]"
[ ! -e "$TMP/.devlog/.span-open" ] && pass "span file removed" || fail "span remains"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
