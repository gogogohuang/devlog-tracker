#!/usr/bin/env bash
# Self-check for round-start.sh + enforce-devlog.sh cooperating through the
# .devlog/.turn-start marker. No framework — plain assert-and-exit, matching
# this repo's existing style. Run directly:
#   bash hooks/scripts/test-enforce-devlog.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/xml-fixture.sh
. "$SCRIPT_DIR/tests/lib/xml-fixture.sh"
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

assert_file_absent() {
  local desc="$1" path="$2"
  if [ ! -e "$path" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected absent: $path)"
    FAIL=1
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (expected to contain '$needle')"; FAIL=1 ;;
  esac
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $desc (expected NOT to contain '$needle')"; FAIL=1 ;;
    *) echo "PASS: $desc" ;;
  esac
}

# Round-current split: enforce-devlog.sh validates .round-current.md now
# (not devlog.md), and merges it into devlog.md on success. One assertion
# per "should succeed" case exercises that merge.
assert_round_merged() {
  local desc="$1" marker="${2:-fixture}"
  assert_file_absent "$desc: .round-current.md merged away" "$DEVLOG_DIR/.round-current.md"
  assert_contains "$desc: content landed in devlog.md" "$marker" "$(cat "$DEVLOG_DIR/devlog.md" 2>/dev/null || true)"
}

# Completes "the round being validated this Stop call": overwrites the
# skeleton round-start.sh just opened in .round-current.md with a full
# Summary/Handoff/Status(DONE) round body (same header shape devlog.md
# rounds use — devlog_merge_round_current appends this verbatim on success).
append_minimal_round() {
  local n="$1" ts="$2"
  cat > "$DEVLOG_DIR/.round-current.md" <<EOF
## Round ${n} — ${ts}

### Summary
fixture

### Reply
fixture reply.

### Handoff
#### 現況
fixture

### Status
DONE
EOF
  xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
}

# Seeds *prior, already-closed* history directly into devlog.md — content
# that is NOT "the round being validated" by an immediately-following
# enforce-devlog.sh call (enforce-devlog.sh only ever reads .round-current.md
# for content validation now).
seed_history_round() {
  local n="$1" ts="$2"
  cat >> "$DEVLOG_DIR/devlog.md" <<EOF
## Round ${n} — ${ts}

### Summary
fixture

### Reply
fixture reply.

### Handoff
#### 現況
fixture

### Status
DONE
EOF
}

# --- Scenario 1: round starts, devlog never touched -> must block ---------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "no write during round -> blocked" 2 $?

# --- Scenario 2: round starts, devlog gets a new Round block -> must pass.
# This whole script runs in well under a second, so round-start.sh's marker
# capture and this write below routinely land in the same wall-clock second
# -- exactly the condition that used to race under the old mtime check.
append_minimal_round 1 "2026-09-08T00:00:00+08:00"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "devlog written this round (same-second race) -> allowed" 0 $?
assert_round_merged "devlog written this round (same-second race)"

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
SPAN_HASH_MISS_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "span open, ticks at max, no write -> blocked (falls back to normal check)" 2 $?
case "$SPAN_HASH_MISS_MSG" in
  *"User Input / Summary / Reply / Handoff / Status"*) echo "PASS: expired-span hash-miss message names all Round sections" ;;
  *) echo "FAIL: expired-span hash-miss message should name User Input / Summary / Reply / Handoff / Status, got: $SPAN_HASH_MISS_MSG"; FAIL=1 ;;
esac
case "$SPAN_HASH_MISS_MSG" in
  *"不要再新增一個 ## Round"*) echo "FAIL: expired-span hash-miss message must not forbid a new Round"; FAIL=1 ;;
  *) echo "PASS: expired-span hash-miss message does not forbid a new Round" ;;
esac
case "$SPAN_HASH_MISS_MSG" in
  *".round-current.md"*'## Round'*) echo "PASS: expired-span hash-miss message points at .round-current.md" ;;
  *) echo "FAIL: expired-span hash-miss message should point at .round-current.md, got: $SPAN_HASH_MISS_MSG"; FAIL=1 ;;
esac
case "$SPAN_HASH_MISS_MSG" in
  *"檔案尾端"*) echo "FAIL: expired-span hash-miss message still says 檔案尾端 (pre round-current-split wording)"; FAIL=1 ;;
  *) echo "PASS: expired-span hash-miss message no longer says 檔案尾端" ;;
esac

# --- Span Mode Scenario 3: ticks at max, devlog IS written this tick ------
# -> allowed, and ticks_since_checkin resets to 0.
append_minimal_round 2 "2026-09-08T00:10:00+08:00"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span open, ticks at max, write happens -> allowed" 0 $?
assert_round_merged "span open, ticks at max, write happens"
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
append_minimal_round 3 "2026-09-08T00:20:00+08:00"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "checkpoint below threshold, round written -> allowed" 0 $?
assert_round_merged "checkpoint below threshold, round written"
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
append_minimal_round 4 "2026-09-08T00:25:00+08:00"
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
append_minimal_round 5 "2026-09-08T00:35:00+08:00"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "malformed .checkpoint-state, round written -> allowed (checkpoint check skipped)" 0 $?
assert_round_merged "malformed .checkpoint-state, round written"

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
: > "$DEVLOG_DIR/devlog.md"
seed_history_round 1 "2026-09-09T00:00:00+08:00"
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
append_minimal_round 2 "2026-09-09T00:05:00+08:00"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "decrease observed on an ordinary (non-checkpoint) write -> allowed (below round threshold)" 0 $?
assert_round_merged "decrease observed on an ordinary (non-checkpoint) write"
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
# round-start.sh opens a skeleton Round first; complete it (Summary+Handoff)
# before the Checkpoint so the last Round is not left incomplete. Both the
# completion and the Checkpoint heading are written into .round-current.md —
# this is the flow Step 9's merge-before-checkpoint-check exists for: a
# "## Checkpoint" written as part of finishing this round is already inside
# devlog.md (merged) by the time the checkpoint-marker count below runs.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/.round-current.md" <<'EOF'

### Summary
fixture

### Reply
fixture reply.

### Handoff
#### 現況
fixture

### Status
DONE

## Checkpoint（Round 2 摘要）
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "genuine checkpoint write above the corrected stored value -> allowed" 0 $?
assert_round_merged "genuine checkpoint write above the corrected stored value" "## Checkpoint（Round 2 摘要）"
CP_ROUNDS_FINAL="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
CP_MARKER_FINAL="$(grep -o '"checkpoint_marker_count"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP_ROUNDS_FINAL" = "0" ] && [ "$CP_MARKER_FINAL" = "1" ]; then
  echo "PASS: genuine checkpoint write past the corrected stored value reset rounds_since_checkpoint to 0 and persisted checkpoint_marker_count to 1 -- resync was not a permanent wedge"
else
  echo "FAIL: expected rounds_since_checkpoint=0 and checkpoint_marker_count=1 after the follow-up genuine write, got rounds=$CP_ROUNDS_FINAL marker=$CP_MARKER_FINAL"
  FAIL=1
fi

# --- Heading check: reset span/checkpoint so only hash + headings matter --
rm -f "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.checkpoint-state"

# --- Heading Scenario 1: hash miss message names Summary / Handoff --------
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 1 — 2026-09-09T10:00:00+08:00

### Summary
prior

### Reply
fixture reply.

### Handoff
#### 現況
prior

### Status
DONE
DEVEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
HASH_MISS_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "no write this round -> blocked (heading tests setup)" 2 $?
case "$HASH_MISS_MSG" in
  *"User Input / Summary / Reply / Handoff / Status"*) echo "PASS: hash-miss message names Summary / Reply / Handoff" ;;
  *) echo "FAIL: hash-miss message should name User Input / Summary / Reply / Handoff / Status, got: $HASH_MISS_MSG"; FAIL=1 ;;
esac
case "$HASH_MISS_MSG" in
  *"User Input / Response / Status"*) echo "FAIL: hash-miss message still names Response"; FAIL=1 ;;
  *) echo "PASS: hash-miss message no longer names Response" ;;
esac
case "$HASH_MISS_MSG" in
  *"編輯最後一個 Round"*) echo "PASS: hash-miss message says edit the last Round" ;;
  *) echo "FAIL: hash-miss message should say 編輯最後一個 Round, got: $HASH_MISS_MSG"; FAIL=1 ;;
esac
case "$HASH_MISS_MSG" in
  *"不要再新增一個 ## Round"*) echo "PASS: hash-miss message forbids a second Round" ;;
  *) echo "FAIL: hash-miss message should say 不要再新增一個 ## Round, got: $HASH_MISS_MSG"; FAIL=1 ;;
esac
case "$HASH_MISS_MSG" in
  *"在檔案尾端補上"*) echo "FAIL: hash-miss message still tells Claude to append a Round"; FAIL=1 ;;
  *) echo "PASS: hash-miss message no longer says 在檔案尾端補上" ;;
esac

# --- Heading Scenario 2: Round written without ### Summary -> blocked -----
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 2 — 2026-09-09T10:05:00+08:00

### Handoff
#### 現況
missing summary

### Status
DONE
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "last Round missing ### Summary -> blocked" 2 $?

# --- Heading Scenario 3: Round written without ### Handoff -> blocked -----
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 3 — 2026-09-09T10:10:00+08:00

### Summary
missing handoff

### Reply
has reply

### Status
DONE
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
HEADING_MISS_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1)"
assert_exit "last Round missing ### Handoff -> blocked" 2 $?
case "$HEADING_MISS_MSG" in
  *'### Summary'*'### Reply'*'### Handoff'*) echo "PASS: heading-miss message names required headings" ;;
  *) echo "FAIL: heading-miss message should mention ### Summary / ### Reply / ### Handoff, got: $HEADING_MISS_MSG"; FAIL=1 ;;
esac
case "$HEADING_MISS_MSG" in
  *"不要再新增一個 ## Round"*) echo "PASS: heading-miss message forbids a second Round" ;;
  *) echo "FAIL: heading-miss message should say 不要再新增一個 ## Round, got: $HEADING_MISS_MSG"; FAIL=1 ;;
esac

# --- Heading Scenario 4: both headings present, empty bodies -> allowed ---
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 4 — 2026-09-09T10:15:00+08:00

### Summary
### Reply
### Handoff
### Status
DONE
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "both headings present with empty bodies -> blocked" 2 $?
EMPTY_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
case "$EMPTY_MSG" in
  *"是空的"*) echo "PASS: empty-body message" ;;
  *) echo "FAIL: empty-body stderr, got: $EMPTY_MSG"; FAIL=1 ;;
esac

# --- Heading Scenario 5: hash changed, content has no "## Round " at all --
# Fixed on review: enforce-devlog.sh must still fail-open (exit 0) when
# .round-current.md's content contains zero "## Round " lines anywhere —
# matching the pre-split last_round_block()'s `if (start == 0) exit 0`
# behavior, and the plan's Global Constraints ("解析不到任何 `## Round`：
# fail-open（不擋）"). Fixed again on the final whole-branch review: this
# content must NOT be merged into devlog.md — there is nothing round-shaped
# here, and merging would silently commit unstructured noise into the
# permanent historical record. .round-current.md is left in place untouched
# so a later turn (or round-start.sh's rescue-merge) can still recover it.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
printf '%s\n' "just a note, not a round" > "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
RC5=$?
assert_exit "no ## Round line at all -> fail-open, allowed" 0 "$RC5"
assert_contains "no ## Round line at all: .round-current.md left untouched" "just a note, not a round" "$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || true)"
assert_not_contains "no ## Round line at all: not merged into devlog.md" "just a note, not a round" "$(cat "$DEVLOG_DIR/devlog.md" 2>/dev/null || true)"

# --- Heading Scenario 6: Checkpoint text must not satisfy headings --------
# Last Round lacks both headings; a following, trailing "## Checkpoint"
# section quotes fully valid-looking Summary/Handoff/Status content. Fixed
# on review: the extraction of .round-current.md must be bounded the same
# way the pre-split last_round_block() was — stop at the next unfenced
# "## " line — so this trailing Checkpoint section can never satisfy the
# Round's own requirements. The fixture is deliberately built so the two
# implementations diverge: a naive whole-file read (the bug) would find
# the quoted headings, bodies, and Status under Checkpoint and wrongly
# allow (exit 0); the bounded read excludes all of that, sees a Round with
# no headings at all, and correctly blocks (exit 2). This makes the
# assertion below a real regression guard, not just an accidental pass.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 5 — 2026-09-09T10:20:00+08:00
old response blob

## Checkpoint（Round 5 摘要）
### Summary
quoted summary text that must not satisfy the Round above

### Handoff
#### 現況
quoted handoff text that must not satisfy the Round above

### Status
DONE
DEVEOF
ERR6="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
RC6=$?
assert_exit "headings only inside trailing Checkpoint -> blocked" 2 "$RC6"
case "$ERR6" in
  *"缺少"*"Summary"*|*"缺少"*"Handoff"*) echo "PASS: blocked for missing headings in the bounded Round, not the Checkpoint's" ;;
  *) echo "FAIL: expected missing-headings message, got: $ERR6"; FAIL=1 ;;
esac

# --- Heading Scenario 7: Checkpoint after completing the open skeleton Round -
# round-start.sh always opens a skeleton; Claude must finish Summary+Handoff
# on that Round. A Checkpoint may follow; the last Round must still have both
# headings. Round 6 is prior, already-merged history (stays in devlog.md);
# round-start.sh opens Round 7's skeleton into .round-current.md, which gets
# completed there. The Checkpoint line is appended straight to devlog.md
# (independent of the round being validated) -- devlog.md content is no
# longer read for round validation at all under the split, so this also
# proves the two are now fully decoupled.
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 6 — 2026-09-09T10:25:00+08:00

### Summary
complete

### Reply
fixture reply.

### Handoff
#### 現況
complete

### Status
DONE
DEVEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'

### Summary
complete

### Reply
fixture reply.

### Handoff
#### 現況
complete

### Status
DONE
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo "## Checkpoint（Round 6 摘要）" >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "Checkpoint-only append after a complete last Round -> allowed" 0 $?
assert_round_merged "Checkpoint-only append after a complete last Round" "complete"

# --- Heading Scenario 8: span one-liner on a complete last Round ----------
# ticks at max so we do not silent-pass; a one-line append must still pass
# heading check because it lands inside the last Round, which already has
# both headings. Span Mode leaves .round-current.md alone across ticks (it
# is the round Claude keeps extending), so the "complete Round" content must
# already be sitting in .round-current.md before round-start.sh captures its
# hash into .turn-start -- otherwise there is nothing for round-start.sh to
# hash in the first place.
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 6 — 2026-09-09T10:25:00+08:00

### Summary
complete

### Reply
fixture reply.

### Handoff
#### 現況
complete

### Status
DONE
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 6,
  "opened_at": "2026-09-09T10:25:00+08:00",
  "ticks_since_checkin": 5,
  "max_silent_ticks": 5
}
SPANEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
echo "span check-in: still looping" >> "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span budget expired, one-line append on complete last Round -> allowed" 0 $?
assert_round_merged "span budget expired, one-line append on complete last Round" "complete"
SPAN_TICKS_ONELINE="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.span-open" | grep -o '[0-9]\+$')"
if [ "$SPAN_TICKS_ONELINE" = "0" ]; then
  echo "PASS: span ticks reset after one-line append that passed heading check"
else
  echo "FAIL: ticks_since_checkin should reset to 0 after passing write, got '$SPAN_TICKS_ONELINE'"
  FAIL=1
fi

# --- Heading Scenario 9: heading miss must not reset span ticks -----------
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 6,
  "opened_at": "2026-09-09T10:25:00+08:00",
  "ticks_since_checkin": 5,
  "max_silent_ticks": 5
}
SPANEOF
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 7 — 2026-09-09T10:30:00+08:00
incomplete new round
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "span at max, new Round missing headings -> blocked" 2 $?
SPAN_TICKS_HELD="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.span-open" | grep -o '[0-9]\+$')"
if [ "$SPAN_TICKS_HELD" = "6" ]; then
  echo "PASS: heading-check failure did not reset ticks_since_checkin (stayed at 6 after round-start increment)"
else
  echo "FAIL: ticks_since_checkin should stay 6 (5 + round-start increment, not reset), got '$SPAN_TICKS_HELD'"
  FAIL=1
fi
rm -f "$DEVLOG_DIR/.span-open"

# --- Heading Scenario 10: fenced ## Round / ## 安裝 must not bound the Round
# A valid last Round has both required headings, but User Input quotes a
# markdown example containing `## Round 15` and `## 安裝`. Those fenced lines
# must not become the last-Round start or the next-heading end.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 8 — 2026-09-09T10:35:00+08:00

### User Input
格式要怎麼寫？

```markdown
## Round 15
## 安裝
```

### Summary
說明 Round 格式。

### Reply
fixture reply.

### Handoff
#### 現況
已回覆格式問題。

### Status
DONE
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "last Round complete, fenced ## Round 15 and ## 安裝 in body -> allowed" 0 $?
assert_round_merged "last Round complete, fenced ## Round 15 and ## 安裝 in body" "已回覆格式問題"

# --- Heading Scenario 11: older ### Response Round must not block last Round
# History may still use ### Response. That older round is genuinely prior,
# already-merged history -- it stays in devlog.md. Only .round-current.md
# (Round 2, the round being validated) is read for content validation now,
# so devlog.md's legacy shape can never interfere with it by construction.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/devlog.md" <<'DEVEOF'
## Round 1 — 2026-09-08T09:00:00+08:00

### User Input
legacy request

### Response
old blob without Summary or Handoff

### Status
DONE
DEVEOF
cat > "$DEVLOG_DIR/.round-current.md" <<'DEVEOF'
## Round 2 — 2026-09-09T10:40:00+08:00

### Summary
new shape

### Reply
fixture reply.

### Handoff
#### 現況
complete last Round

### Status
DONE
DEVEOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "older Round still uses ### Response, complete last Round -> allowed" 0 $?
assert_round_merged "older Round still uses ### Response, complete last Round" "complete last Round"

# --- Recording moments: skeleton hash-equal still blocks -------------------
rm -f "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.checkpoint-state" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.interrupted"
: > "$DEVLOG_DIR/devlog.md"
printf '%s' '{"prompt":"block me"}' | bash "$SCRIPT_DIR/round-start.sh"
printf '%s\n' 'main @ deadbeef，工作樹乾淨' > "$DEVLOG_DIR/.workspace-mismatch"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "skeleton only (hash equal after submit write) -> blocked" 2 $?
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "PASS: .round-open remains after hash-miss block"
else
  echo "FAIL: .round-open should remain when Stop blocks"
  FAIL=1
fi
if [ -f "$DEVLOG_DIR/.workspace-mismatch" ]; then
  echo "PASS: .workspace-mismatch remains after hash-miss block"
else
  echo "FAIL: .workspace-mismatch should remain when Stop blocks"
  FAIL=1
fi

# --- Recording moments: Summary+Handoff on same Round deletes .round-open --
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
block me
```

### Summary
done

### Reply
fixture reply.

### Handoff
#### 現況
done

### Status
DONE
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
printf '%s\n' 'main @ deadbeef，工作樹乾淨' > "$DEVLOG_DIR/.workspace-mismatch"
cksum < "$DEVLOG_DIR/.round-current.md" > "$DEVLOG_DIR/.turn-start"
# Hash equal would block — simulate Claude's edit by appending a newline after snapshot:
printf '\n' >> "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "headings present and hash changed -> allowed" 0 $?
assert_round_merged "headings present and hash changed" "done"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: .round-open should be deleted on successful Stop"
  FAIL=1
else
  echo "PASS: .round-open deleted after successful close"
fi
if [ -f "$DEVLOG_DIR/.workspace-mismatch" ]; then
  echo "FAIL: .workspace-mismatch should be deleted on successful Stop"
  FAIL=1
else
  echo "PASS: .workspace-mismatch deleted after successful close"
fi

# --- Recording moments: .interrupted stamps and does not block -------------
# The dangling round content lives in .round-current.md now (Task 3);
# close-open-round.sh stamps it INTERRUPTED there and merges it into
# devlog.md, removing .round-current.md -- the key new behavior this task's
# retargeted short-circuit (Step 1) depends on.
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
esc
```


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/.round-current.md" > "$DEVLOG_DIR/.turn-start"
touch "$DEVLOG_DIR/.interrupted"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit ".interrupted -> exit 0 (does not fight Esc)" 0 $?
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
case "$BODY" in
  *INTERRUPTED*) echo "PASS: .interrupted stamped INTERRUPTED" ;;
  *) echo "FAIL: expected INTERRUPTED after .interrupted Stop"; FAIL=1 ;;
esac
case "$BODY" in
  *user_interrupt*) echo "PASS: reason is user_interrupt" ;;
  *) echo "FAIL: expected user_interrupt reason"; FAIL=1 ;;
esac
if [ -f "$DEVLOG_DIR/.interrupted" ] || [ -f "$DEVLOG_DIR/.round-open" ] || [ -f "$DEVLOG_DIR/.round-current.md" ]; then
  echo "FAIL: interrupt path should delete both markers and merge round-current away"
  FAIL=1
else
  echo "PASS: interrupt path deleted markers and merged round-current away"
fi

# --- Recording moments: completed round + .interrupted must NOT stamp ------
# Esc/is_interrupt fired, but Claude recovered and wrote Summary+Handoff.
# Stop must clear the marker and take the normal success path — not overwrite
# a finished Round to INTERRUPTED. This is the "recovered" outcome from
# close-open-round.sh: it still merges .round-current.md into devlog.md
# (Task 3's design change), so this Stop invocation's own .round-current.md
# check (Step 1) correctly finds nothing left to validate and exits 0.
# devlog.md is reset first: by this point it has accumulated merged content
# from earlier scenarios in this file (including the previous scenario's
# genuine INTERRUPTED stamp), and the BODY check below only cares about what
# this call itself merges.
: > "$DEVLOG_DIR/devlog.md"
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
recover
```

### Summary
recovered after interrupt

### Reply
fixture reply.

### Handoff
#### 現況
round finished normally

### Status
DONE
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/.round-current.md" > "$DEVLOG_DIR/.turn-start"
printf '\n' >> "$DEVLOG_DIR/.round-current.md"
touch "$DEVLOG_DIR/.interrupted"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "complete last Round + .interrupted + hash changed -> exit 0" 0 $?
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
case "$BODY" in
  *INTERRUPTED*) echo "FAIL: completed Round must not be stamped INTERRUPTED"; FAIL=1 ;;
  *) echo "PASS: completed Round Status left as written (not INTERRUPTED)" ;;
esac
case "$BODY" in
  *DONE*) echo "PASS: Status DONE preserved" ;;
  *) echo "FAIL: expected Status DONE to remain"; FAIL=1 ;;
esac
if [ -f "$DEVLOG_DIR/.interrupted" ] || [ -f "$DEVLOG_DIR/.round-open" ] || [ -f "$DEVLOG_DIR/.round-current.md" ]; then
  echo "FAIL: recovered-complete path should delete .interrupted/.round-open and merge round-current away"
  FAIL=1
else
  echo "PASS: recovered-complete path deleted markers and merged round-current away"
fi

# --- Recording moments: interrupted-and-recovered short-circuit reads
# .round-current.md's presence directly (Step 1), not a devlog.md string
# match. Separate throwaway project dir so it doesn't disturb $DEVLOG_DIR's
# ongoing state above.
RECOVER_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$RECOVER_DIR"
mkdir -p "$RECOVER_DIR/.devlog"
touch "$RECOVER_DIR/.devlog/.enabled"
: > "$RECOVER_DIR/.devlog/devlog.md"
printf '## Round 1 — 2026-09-17T09:00:00+0800\n\n### User Input\n```text\nX\n```\n\n### Summary\n完成\n\n### Handoff\n#### 現況\nok\n\n### Status\nDONE\n' > "$RECOVER_DIR/.devlog/.round-current.md"
xml_fixture_handoff_only "$RECOVER_DIR/.devlog/.round-current.md"
printf '{"round": 1}\n' > "$RECOVER_DIR/.devlog/.round-open"
echo "stale" > "$RECOVER_DIR/.devlog/.turn-start"
touch "$RECOVER_DIR/.devlog/.interrupted"

echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
RC=$?
assert_exit "recovered-through-stop: exits 0" 0 "$RC"
assert_file_absent "recovered-through-stop: .round-current.md merged away" "$RECOVER_DIR/.devlog/.round-current.md"
MAIN_AFTER="$(cat "$RECOVER_DIR/.devlog/devlog.md")"
assert_contains "recovered-through-stop: content landed in devlog.md" "完成" "$MAIN_AFTER"
rm -rf "$RECOVER_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

# --- Recording moments: stale .interrupted without .round-open -------------
# A leftover .interrupted must not permanently short-circuit Stop when there
# is no open round — the next Stop must run normal hash/heading enforcement.
# With no .round-open, close-open-round.sh no-ops and leaves .round-current.md
# untouched (Task 3) -- Step 1's redesigned short-circuit must then find it
# still non-empty and fall through to normal enforcement, not exit 0.
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
stale interrupt
```


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
cksum < "$DEVLOG_DIR/.round-current.md" > "$DEVLOG_DIR/.turn-start"
rm -f "$DEVLOG_DIR/.round-open"
touch "$DEVLOG_DIR/.interrupted"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "stale .interrupted, no .round-open -> normal enforcement blocks" 2 $?
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: first Stop should clear .interrupted even without .round-open"
  FAIL=1
else
  echo "PASS: stale .interrupted cleared on first Stop"
fi
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "after stale interrupt cleared -> normal enforcement blocks (hash equal)" 2 $?

# --- Recording moments: loop guard leaves .round-open ----------------------
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
echo '{"stop_hook_active":true}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "loop guard -> exit 0" 0 $?
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "PASS: loop guard did not delete .round-open"
else
  echo "FAIL: loop guard should leave .round-open for later heal"
  FAIL=1
fi

# --- Recording moments: paused project drops stale .interrupted ------------
rm -f "$DEVLOG_DIR/.enabled" "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
touch "$DEVLOG_DIR/.interrupted"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "disabled project with .interrupted -> exits 0" 0 $?
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: disabled project Stop should delete stale .interrupted"
  FAIL=1
else
  echo "PASS: disabled project Stop deleted stale .interrupted"
fi
if [ -e "$DEVLOG_DIR/devlog.md" ]; then
  echo "FAIL: disabled project Stop should not create devlog.md"
  FAIL=1
else
  echo "PASS: disabled project Stop did not create or edit devlog.md"
fi

# --- Heading Scenario 12: legal DONE with bodies, no 下一步 -> allowed ----
touch "$DEVLOG_DIR/.enabled"
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 90 — 2026-09-09T10:40:00+08:00

### Summary
一句話。

### Reply
fixture reply.

### Handoff
#### 現況
做完了。

### Status
DONE
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "DONE with bodies and no 下一步 -> allowed" 0 $?
assert_round_merged "DONE with bodies and no 下一步" "做完了"

# --- Heading Scenario 13: IN_PROGRESS without 下一步 -> blocked -----------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 91 — 2026-09-09T10:41:00+08:00

### Summary
還在做。

### Reply
fixture reply.

### Handoff
#### 現況
做到一半。


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "IN_PROGRESS without 下一步 -> blocked" 2 $?

# --- Heading Scenario 14: IN_PROGRESS with 下一步 -> allowed --------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 92 — 2026-09-09T10:42:00+08:00

### Summary
還在做。

### Reply
fixture reply.

### Handoff
#### 工作區
非 git 工作區
#### 現況
做到一半。
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
打開 foo.ts 繼續。


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "IN_PROGRESS with 下一步 -> allowed" 0 $?
assert_round_merged "IN_PROGRESS with 下一步" "打開 foo.ts 繼續"

# --- Heading Scenario 15: illegal Status -> blocked -----------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 93 — 2026-09-09T10:43:00+08:00

### Summary
x

### Reply
fixture reply.

### Handoff
#### 現況
y

### Status
WIP
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "illegal Status -> blocked" 2 $?

# --- Next-step blacklist Scenario 1: pure filler phrase -> blocked --------
# (docs/design/next-step-blacklist.md)
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 94 — 2026-09-09T10:44:00+08:00

### Summary
還在做。

### Reply
fixture reply.

### Handoff
#### 現況
做到一半。
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
繼續完成


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
BLACKLIST_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
assert_exit "下一步 is pure filler phrase '繼續完成' -> blocked" 2 $?
case "$BLACKLIST_MSG" in
  *"是空話"*) echo "PASS: filler-phrase message names it as 空話" ;;
  *) echo "FAIL: expected filler-phrase message, got: $BLACKLIST_MSG"; FAIL=1 ;;
esac

# --- Next-step blacklist Scenario 2: filler phrase with trailing 。 --------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 95 — 2026-09-09T10:45:00+08:00

### Summary
還在做。

### Reply
fixture reply.

### Handoff
#### 現況
做到一半。
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
#### 下一步
持續優化。


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
BLOCKED
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "下一步 is '持續優化。' with trailing punctuation -> blocked (BLOCKED status too)" 2 $?

# --- Next-step blacklist Scenario 3: phrase embedded in a longer sentence -
# Must NOT block -- only an exact whole-body match is filler.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 96 — 2026-09-09T10:46:00+08:00

### Summary
還在做。

### Reply
fixture reply.

### Handoff
#### 工作區
非 git 工作區
#### 現況
做到一半。
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
先繼續完成 foo.ts 的錯誤處理，再跑一次測試。


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "下一步 contains 繼續完成 inside a concrete sentence -> allowed" 0 $?
assert_round_merged "下一步 contains 繼續完成 inside a concrete sentence" "錯誤處理"

# --- Next-step blacklist Scenario 4: multi-line body, one line is filler --
# Must NOT block -- the blacklist only fires when the whole body is a
# single line.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 97 — 2026-09-09T10:47:00+08:00

### Summary
還在做。

### Reply
fixture reply.

### Handoff
#### 工作區
非 git 工作區
#### 現況
做到一半。
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
繼續完成
打開 bar.ts 補上測試。


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "下一步 multi-line body including a filler line -> allowed" 0 $?
assert_round_merged "下一步 multi-line body including a filler line" "bar.ts"

# --- L1: missing ### Reply -> blocked --------------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 98 — 2026-09-15T10:00:00+08:00

### Summary
x

### Handoff
#### 現況
y

### Status
DONE
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
REPLY_MISS_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
assert_exit "last Round missing ### Reply -> blocked" 2 $?
case "$REPLY_MISS_MSG" in
  *'### Reply'*) echo "PASS: missing-Reply message names ### Reply" ;;
  *) echo "FAIL: expected ### Reply in message, got: $REPLY_MISS_MSG"; FAIL=1 ;;
esac

# --- L1: IN_PROGRESS 下一步 without actionable signal -> blocked ------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 99 — 2026-09-15T10:01:00+08:00

### Summary
還在做。

### Reply
還在處理。

### Handoff
#### 工作區
非 git 工作區
#### 現況
做到一半。
#### 完成條件
功能可用。
#### 下一步
再想一下怎麼做比較好


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
ACTION_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
assert_exit "IN_PROGRESS 下一步 without path/cmd/skill -> blocked" 2 $?
case "$ACTION_MSG" in
  *"可執行跡象"*) echo "PASS: actionable-lint message" ;;
  *) echo "FAIL: expected 可執行跡象 message, got: $ACTION_MSG"; FAIL=1 ;;
esac

# --- L1: BLOCKED without 缺件句式 -> blocked --------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 100 — 2026-09-15T10:02:00+08:00

### Summary
卡住。

### Reply
需要更多資訊。

### Handoff
#### 工作區
非 git 工作區
#### 現況
做到一半。
#### 完成條件
拿到資料後把 hooks/foo.sh 改完。
#### 下一步
改 hooks/foo.sh


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
BLOCKED
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
BLOCKED_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
assert_exit "BLOCKED without 缺件句式 -> blocked" 2 $?
case "$BLOCKED_MSG" in
  *"缺什麼"*) echo "PASS: BLOCKED 缺件 message" ;;
  *) echo "FAIL: expected 缺什麼 message, got: $BLOCKED_MSG"; FAIL=1 ;;
esac

# --- L1: BLOCKED with 缺件句式 -> allowed -----------------------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 101 — 2026-09-15T10:03:00+08:00

### Summary
卡住。

### Reply
還在等 API key。

### Handoff
#### 工作區
非 git 工作區
#### 現況
缺使用者提供的 API key（寫進 .env 即算到）。
#### 完成條件
.env 有 key 且 hooks/foo.sh 改完。
#### 下一步
等使用者提供 key 後改 hooks/foo.sh


### Session Handoff

#### 決策
- （無）

#### 待解問題
- fixture open

#### 失敗嘗試
- （無）

### Status
BLOCKED
EOF
xml_fixture_handoff_only "$DEVLOG_DIR/.round-current.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "BLOCKED with 缺件句式 -> allowed" 0 $?

# --- Lock contention: another live session holds .devlog/.lock -----------
# Must block (exit 2, distinct message) instead of proceeding to read/merge
# a devlog.md that the other session might be mid-write on, and must leave
# .round-current.md / devlog.md untouched so the retry has something to
# validate.
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
append_minimal_round 102 "2026-09-15T10:04:00+08:00"
PRE_ROUND_CURRENT="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || true)"
PRE_DEVLOG="$(cat "$DEVLOG_DIR/devlog.md" 2>/dev/null || true)"
sleep 5 &
LOCK_HOLDER_PID=$!
mkdir "$DEVLOG_DIR/.lock"
echo "$LOCK_HOLDER_PID" > "$DEVLOG_DIR/.lock/pid"
CONTENTION_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
assert_exit "another live session holds the lock -> blocked" 2 $?
case "$CONTENTION_MSG" in
  *"$LOCK_HOLDER_PID"*) echo "PASS: contention message names the holder pid" ;;
  *) echo "FAIL: expected holder pid $LOCK_HOLDER_PID in message, got: $CONTENTION_MSG"; FAIL=1 ;;
esac
assert_contains "lock contention: .round-current.md left untouched" "$PRE_ROUND_CURRENT" "$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || true)"
[ "$(cat "$DEVLOG_DIR/devlog.md" 2>/dev/null || true)" = "$PRE_DEVLOG" ] \
  && echo "PASS: lock contention: devlog.md left untouched" \
  || { echo "FAIL: devlog.md should be untouched while the lock is contended"; FAIL=1; }
kill "$LOCK_HOLDER_PID" 2>/dev/null || true
wait "$LOCK_HOLDER_PID" 2>/dev/null || true
rm -rf "$DEVLOG_DIR/.lock"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "retry once the lock is free -> allowed (no lasting side effect)" 0 $?
assert_round_merged "retry once the lock is free" "fixture"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi

