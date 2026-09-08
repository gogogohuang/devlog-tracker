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

# --- Checkpoint Mode Scenario 1: below threshold, no checkpoint yet -------
# round-start.sh should bump rounds_since_checkpoint from 0 to 1; a normal
# round write still satisfies the base hash check, so this must pass and
# leave the counter at 1 (untouched, since no new "## Checkpoint" appeared).
rm -f "$DEVLOG_DIR/.span-open"
cat > "$DEVLOG_DIR/.checkpoint-state" <<'CPEOF'
{"rounds_since_checkpoint": 0, "max_silent_rounds": 2, "checkpoint_marker_count": 0}
CPEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo "## Round 3 — 2026-09-08T00:20:00+08:00" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "checkpoint below threshold, round written -> allowed" 0 $?
CP_ROUNDS_AFTER="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP_ROUNDS_AFTER" = "1" ]; then
  echo "PASS: round-start.sh incremented rounds_since_checkpoint to 1"
else
  echo "FAIL: rounds_since_checkpoint should be 1, got '$CP_ROUNDS_AFTER'"
  FAIL=1
fi

# --- Checkpoint Mode Scenario 2: threshold reached, no checkpoint written -
# max_silent_rounds is 2; this is the second round-start.sh increment
# (1 -> 2), so rounds_since_checkpoint hits the threshold. Even though the
# round writes normal content (satisfying the base hash check), no
# "## Checkpoint" heading exists yet -> must be blocked.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo "## Round 4 — 2026-09-08T00:25:00+08:00" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "checkpoint threshold reached, no checkpoint block -> blocked" 2 $?

# --- Checkpoint Mode Scenario 3: checkpoint block written -> resolves it --
# Simulates Claude responding to the block by appending a checkpoint
# heading. The retry must pass and reset both counters.
echo "## Checkpoint（Round 3-4 摘要）" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "checkpoint block written -> allowed" 0 $?
CP_ROUNDS_RESET="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
CP_MARKER_AFTER="$(grep -o '"checkpoint_marker_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP_ROUNDS_RESET" = "0" ] && [ "$CP_MARKER_AFTER" = "1" ]; then
  echo "PASS: checkpoint write reset rounds_since_checkpoint to 0 and checkpoint_marker_count to 1"
else
  echo "FAIL: expected rounds_since_checkpoint=0 and checkpoint_marker_count=1, got rounds=$CP_ROUNDS_RESET marker=$CP_MARKER_AFTER"
  FAIL=1
fi

# --- Checkpoint Mode Scenario 4: an open, under-budget span pauses the ----
# checkpoint counter, so it doesn't get double-jeopardy'd during an
# automated run that Span Mode is deliberately keeping quiet.
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 4,
  "opened_at": "2026-09-08T00:30:00+08:00",
  "ticks_since_checkin": 0,
  "max_silent_ticks": 5
}
SPANEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
CP_ROUNDS_DURING_SPAN="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP_ROUNDS_DURING_SPAN" = "0" ]; then
  echo "PASS: rounds_since_checkpoint not incremented while span silently passes this tick"
else
  echo "FAIL: rounds_since_checkpoint should stay 0 during span pass-through, got '$CP_ROUNDS_DURING_SPAN'"
  FAIL=1
fi
rm -f "$DEVLOG_DIR/.span-open"

# --- Checkpoint Mode Scenario 5: malformed .checkpoint-state -> fail-open -
echo "not valid json at all" > "$DEVLOG_DIR/.checkpoint-state"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "malformed .checkpoint-state, no write this round -> blocked by normal check only" 2 $?
echo "## Round 5 — 2026-09-08T00:35:00+08:00" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "malformed .checkpoint-state, round written -> allowed (checkpoint check skipped)" 0 $?

# --- Checkpoint Mode Scenario 6: stored count higher than live count ------
# (simulating post-archival/manual-edit decrease). Proves the resync guard
# actually persists the corrected (lower) checkpoint_marker_count to disk
# the moment the decrease is observed -- not just in the shell variable for
# one invocation -- since this script is a fresh process every Stop hook
# call and can only ever see what's on disk. Also proves a bare decrease
# must not touch rounds_since_checkpoint, and that the very next genuine
# checkpoint write correctly resets both counters off the now-correct base.
cat > "$DEVLOG_DIR/.checkpoint-state" <<'CPEOF'
{"rounds_since_checkpoint": 3, "max_silent_rounds": 20, "checkpoint_marker_count": 1}
CPEOF
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 1 — 2026-09-09T00:00:00+08:00
DEVEOF
# devlog.md now has 0 "## Checkpoint" headings, but checkpoint_marker_count
# says 1 (stale, from before an archival/manual edit removed it): live (0) <
# stored (1) -- the decrease case.

# Round A: round-start.sh bumps rounds_since_checkpoint 3 -> 4, then Claude
# writes an ORDINARY round block (no new "## Checkpoint" heading) -- this
# satisfies the base hash check but leaves the live checkpoint-heading count
# at 0, still below the stale stored value of 1. This is the moment
# enforce-devlog.sh must observe the decrease and persist it immediately,
# without waiting for any future checkpoint write.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo "## Round 2 — 2026-09-09T00:05:00+08:00" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "decrease observed on an ordinary (non-checkpoint) write -> allowed (below round threshold)" 0 $?
CP_ROUNDS_MID="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
CP_MARKER_MID="$(grep -o '"checkpoint_marker_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP_ROUNDS_MID" = "4" ] && [ "$CP_MARKER_MID" = "0" ]; then
  echo "PASS: downward-count observation persisted checkpoint_marker_count=0 to disk IMMEDIATELY (before any new checkpoint heading existed), while leaving rounds_since_checkpoint at round-start.sh's plain increment (not reset)"
else
  echo "FAIL: expected rounds_since_checkpoint=4 (untouched by resync) and checkpoint_marker_count=0 (persisted to disk by the resync itself), got rounds=$CP_ROUNDS_MID marker=$CP_MARKER_MID"
  FAIL=1
fi

# Round B: a genuine checkpoint write now brings the live count to 1, which
# is above the just-corrected stored value of 0 -- the normal -gt path must
# fire and reset/persist both counters together, proving a real checkpoint
# write is never blocked or wedged after a resync.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo "## Checkpoint（Round 2 摘要）" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "genuine checkpoint write above the corrected stored value -> allowed" 0 $?
CP_ROUNDS_FINAL="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
CP_MARKER_FINAL="$(grep -o '"checkpoint_marker_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP_ROUNDS_FINAL" = "0" ] && [ "$CP_MARKER_FINAL" = "1" ]; then
  echo "PASS: genuine checkpoint write past the corrected stored value reset rounds_since_checkpoint to 0 and persisted checkpoint_marker_count to 1 -- resync was not a permanent wedge"
else
  echo "FAIL: expected rounds_since_checkpoint=0 and checkpoint_marker_count=1 after the follow-up genuine write, got rounds=$CP_ROUNDS_FINAL marker=$CP_MARKER_FINAL"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
