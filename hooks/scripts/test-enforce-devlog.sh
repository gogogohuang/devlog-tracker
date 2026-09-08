#!/usr/bin/env bash
# Self-check for round-start.sh + enforce-devlog.sh cooperating through the
# .devlog/.turn-start marker. No framework — plain assert-and-exit, matching
# this repo's existing style. Run directly:
#   bash hooks/scripts/test-enforce-devlog.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# --- Scenario 1: round starts, devlog never touched -> must block ---------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "no write during round -> blocked" 2 $?

# --- Scenario 2: round starts, devlog gets a new Round block -> must pass.
# This whole script runs in well under a second, so round-start.sh's marker
# capture and this write below routinely land in the same wall-clock second
# -- exactly the condition that used to race under the old mtime check.
echo "## Round 1 — 2026-09-08T00:00:00+08:00" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "devlog written this round (same-second race) -> allowed" 0 $?

# --- Scenario 3: next round starts, devlog NOT touched again -> must block
# again, proving the marker was correctly refreshed and isn't just "always
# pass after the first write".
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "no write in the following round -> blocked again" 2 $?

# --- Scenario 4: stop_hook_active guard must work even without jq --------
PATH_NO_JQ="$TMP_ROOT/no-jq-path"
mkdir -p "$PATH_NO_JQ"
for bin in bash cat printf cksum; do
  bin_path="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$bin_path" ] && ln -sf "$bin_path" "$PATH_NO_JQ/$bin"
done
echo '{"stop_hook_active":true}' | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "stop_hook_active=true without jq -> exits 0 immediately" 0 $?

# Regression: false positive when another field contains "true" after stop_hook_active
echo '{"stop_hook_active":false,"other":true}' | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "stop_hook_active=false with other:true -> does NOT short-circuit (blocks due to empty devlog)" 2 $?

# Regression: false positive with typo in field name but "true" appears later
echo '{"stop_hock_active":false,"transcript_path":"/tmp/xtrue.jsonl"}' | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "misspelled field with 'true' in path -> does NOT short-circuit (blocks due to empty devlog)" 2 $?

# --- Span Mode Scenario 1: span open, ticks below max, no write -----------
# -> allowed even though nothing was written this tick; round-start.sh must
# have incremented ticks_since_checkin from 0 to 1.
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 1,
  "opened_at": "2026-09-08T00:00:00+08:00",
  "ticks_since_checkin": 0,
  "max_silent_ticks": 5
}
SPANEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span open, ticks below max, no write -> allowed" 0 $?
SPAN_TICKS_AFTER="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.span-open" | grep -o '[0-9]\+$')"
if [ "$SPAN_TICKS_AFTER" = "1" ]; then
  echo "PASS: round-start.sh incremented ticks_since_checkin to 1"
else
  echo "FAIL: round-start.sh should have incremented ticks_since_checkin to 1, got '$SPAN_TICKS_AFTER'"
  FAIL=1
fi

# --- Span Mode Scenario 2: ticks reach max, devlog still untouched --------
# -> falls back to normal enforcement, blocks.
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 1,
  "opened_at": "2026-09-08T00:00:00+08:00",
  "ticks_since_checkin": 5,
  "max_silent_ticks": 5
}
SPANEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span open, ticks at max, no write -> blocked (falls back to normal check)" 2 $?

# --- Span Mode Scenario 3: ticks at max, devlog IS written this tick ------
# -> allowed, and ticks_since_checkin resets to 0.
echo "## Round 2 — 2026-09-08T00:10:00+08:00" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span open, ticks at max, write happens -> allowed" 0 $?
SPAN_TICKS_RESET="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.span-open" | grep -o '[0-9]\+$')"
if [ "$SPAN_TICKS_RESET" = "0" ]; then
  echo "PASS: ticks_since_checkin reset to 0 after a successful write"
else
  echo "FAIL: ticks_since_checkin should have reset to 0, got '$SPAN_TICKS_RESET'"
  FAIL=1
fi

# --- Span Mode Scenario 4: malformed .span-open -> treated as absent ------
echo "not valid json at all" > "$DEVLOG_DIR/.span-open"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "malformed .span-open -> falls through to normal check, blocked (no write)" 2 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
