#!/usr/bin/env bash
# Self-check for session-start-devlog.sh, including the Span Mode
# resume-context note. No framework — plain assert-and-exit, matching this
# repo's existing style. Run directly:
#   bash hooks/scripts/test-session-start-devlog.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"

FAIL=0
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (expected output to contain: $needle)"; FAIL=1 ;;
  esac
}
assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $desc (expected output NOT to contain: $needle)"; FAIL=1 ;;
    *) echo "PASS: $desc" ;;
  esac
}

# --- Scenario 1: no devlog.md, no span -> silent exit 0 -------------------
OUTPUT="$(bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ] && [ -z "$OUTPUT" ]; then
  echo "PASS: no devlog.md, no span -> silent exit 0"
else
  echo "FAIL: no devlog.md, no span -> expected silent exit 0, got exit $EXIT_CODE, output: $OUTPUT"
  FAIL=1
fi

# --- Scenario 2: devlog.md exists, no span -> normal output, no span note -
echo "## Round 1 — 2026-09-08T00:00:00+08:00" >> "$DEVLOG_DIR/devlog.md"
OUTPUT="$(bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_not_contains "no span -> no span warning in output" "開啟中的 span" "$OUTPUT"
assert_contains "no span -> still shows devlog content" "Round 1" "$OUTPUT"

# --- Scenario 3: span open with valid round/opened_at -> warning shown ----
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 1,
  "opened_at": "2026-09-08T21:40:00+08:00",
  "ticks_since_checkin": 2,
  "max_silent_ticks": 5
}
SPANEOF
OUTPUT="$(bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "span open -> warning mentions Round 1" "Round 1" "$OUTPUT"
assert_contains "span open -> warning mentions opened_at timestamp" "2026-09-08T21:40:00+08:00" "$OUTPUT"
assert_contains "span open -> warning mentions .span-open" ".span-open" "$OUTPUT"

# --- Scenario 4: span file malformed -> no warning, no crash --------------
echo "not valid json" > "$DEVLOG_DIR/.span-open"
OUTPUT="$(bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
EXIT_CODE=$?
assert_not_contains "malformed span -> no warning shown" "開啟中的 span" "$OUTPUT"
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "PASS: malformed span -> still exits 0"
else
  echo "FAIL: malformed span -> expected exit 0, got $EXIT_CODE"
  FAIL=1
fi

# --- Scenario 5: open round is stamped INTERRUPTED then still injected ------
rm -f "$DEVLOG_DIR/.span-open"
touch "$DEVLOG_DIR/.enabled"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
crash me
```

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
OUTPUT="$(bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "session start still shows Round 1" "Round 1" "$OUTPUT"
assert_contains "session start output includes INTERRUPTED" "INTERRUPTED" "$OUTPUT"
assert_contains "heal reason in the file/output" "dangling:session_start" "$OUTPUT"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: SessionStart should delete .round-open after heal"
  FAIL=1
else
  echo "PASS: SessionStart deleted .round-open"
fi
FILE="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "file stamped INTERRUPTED" "INTERRUPTED" "$FILE"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
