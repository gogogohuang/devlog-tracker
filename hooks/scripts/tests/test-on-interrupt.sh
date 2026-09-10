#!/usr/bin/env bash
# Self-check for on-stop-failure.sh / on-session-end.sh / on-tool-failure.sh.
# Run: bash hooks/scripts/test-on-interrupt.sh
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
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (missing: $needle)"; FAIL=1 ;;
  esac
}

write_open() {
  cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### Status
IN_PROGRESS
EOF
  printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
}

# usage skips
for err in rate_limit billing_error account_on_hold; do
  write_open
  echo "{\"error\":\"$err\"}" | bash "$SCRIPT_DIR/on-stop-failure.sh"
  assert_exit "StopFailure $err -> exit 0" 0 $?
  BODY="$(cat "$DEVLOG_DIR/devlog.md")"
  case "$BODY" in
    *INTERRUPTED*) echo "FAIL: $err must not stamp INTERRUPTED"; FAIL=1 ;;
    *) echo "PASS: $err left Status IN_PROGRESS" ;;
  esac
  if [ -f "$DEVLOG_DIR/.round-open" ]; then
    echo "PASS: $err left .round-open"
  else
    echo "FAIL: $err should not close .round-open"
    FAIL=1
  fi
done

# server_error stamps
write_open
echo '{"error":"server_error"}' | bash "$SCRIPT_DIR/on-stop-failure.sh"
assert_exit "StopFailure server_error -> exit 0" 0 $?
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "server_error status" "INTERRUPTED" "$BODY"
assert_contains "server_error reason" "StopFailure:server_error" "$BODY"

# missing error -> unknown
write_open
echo '{}' | bash "$SCRIPT_DIR/on-stop-failure.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "missing error -> unknown" "StopFailure:unknown" "$BODY"

# SessionEnd with marker
write_open
echo '{"reason":"clear"}' | bash "$SCRIPT_DIR/on-session-end.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "session end reason" "SessionEnd:clear" "$BODY"

# SessionEnd without marker
write_open
rm -f "$DEVLOG_DIR/.round-open"
BEFORE="$(cat "$DEVLOG_DIR/devlog.md")"
echo '{"reason":"other"}' | bash "$SCRIPT_DIR/on-session-end.sh"
AFTER="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: SessionEnd without .round-open is a no-op"
else
  echo "FAIL: SessionEnd edited a closed Round"
  FAIL=1
fi

# PostToolUseFailure interrupt
rm -f "$DEVLOG_DIR/.interrupted"
echo '{"is_interrupt":true}' | bash "$SCRIPT_DIR/on-tool-failure.sh"
assert_exit "tool failure interrupt -> exit 0" 0 $?
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "PASS: is_interrupt created .interrupted"
else
  echo "FAIL: .interrupted missing"
  FAIL=1
fi
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
case "$BODY" in
  *INTERRUPTED*) echo "FAIL: on-tool-failure must not patch devlog.md"; FAIL=1 ;;
  *) echo "PASS: on-tool-failure did not patch devlog.md" ;;
esac

# is_interrupt false
rm -f "$DEVLOG_DIR/.interrupted"
echo '{"is_interrupt":false}' | bash "$SCRIPT_DIR/on-tool-failure.sh"
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: is_interrupt false should not create the marker"
  FAIL=1
else
  echo "PASS: is_interrupt false created no marker"
fi

# no .enabled -> no marker
rm -f "$DEVLOG_DIR/.enabled" "$DEVLOG_DIR/.interrupted"
echo '{"is_interrupt":true}' | bash "$SCRIPT_DIR/on-tool-failure.sh"
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: disabled project must not create .interrupted"
  FAIL=1
else
  echo "PASS: disabled -> no .interrupted"
fi

# SessionEnd on a completed open Round must not stamp
touch "$DEVLOG_DIR/.enabled"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
done
```

### Summary
finished

### Handoff
#### 現況
finished

### Status
DONE
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/devlog.md" > "$DEVLOG_DIR/.turn-start"
printf '\n' >> "$DEVLOG_DIR/devlog.md"
echo '{"reason":"clear"}' | bash "$SCRIPT_DIR/on-session-end.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
case "$BODY" in
  *INTERRUPTED*) echo "FAIL: SessionEnd must not stamp a completed Round"; FAIL=1 ;;
  *) echo "PASS: SessionEnd left completed Status DONE" ;;
esac
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: SessionEnd recovered-complete should delete .round-open"
  FAIL=1
else
  echo "PASS: SessionEnd recovered-complete deleted .round-open"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
