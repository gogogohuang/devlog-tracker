# Recording Moments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist each interactive round at submit, require Summary/Handoff on a normal Stop, and stamp the same Round `INTERRUPTED` on unexpected interrupt (not usage exhaustion).

**Architecture:** `UserPromptSubmit` appends a skeleton Round and `.round-open`, then snapshots `.turn-start` *after* that write so Stop still demands a Claude edit. A shared `close-open-round.sh` patches the matching last Round to `INTERRUPTED`. Stop short-circuits on `.interrupted` before the loop guard. Span ticks still skip new Rounds. Segment Watch is unchanged except its round-start clock follows the post-skeleton hash.

**Tech Stack:** bash hooks, `cksum`, `date`, optional `jq`, fence-aware awk already used in `enforce-devlog.sh`; assert-and-exit self-checks (`bash hooks/scripts/test-*.sh`).

## Global Constraints

- Spec: `docs/design/recording-moments.md`. Do not parse `transcript_path`. Do not bump plugin version. Do not port Cursor hooks.
- Completeness remains `### Summary` + `### Handoff` presence-only (no `### Response` check, no body quality checks).
- `.turn-start` is captured **after** the skeleton write. Span budget expiry still uses that hash.
- `.round-open` is the only open-round lock. Interrupt/heal run only when it exists.
- Usage skip is exactly `rate_limit`, `billing_error`, `account_on_hold`. All other StopFailure `error` values stamp `INTERRUPTED`.
- Fail-open: missing `.enabled` → no new `.devlog` files; helper scripts always `exit 0`.
- Hooks may author `devlog.md` **only** for the skeleton and the interrupt stamp. `segment-watch.sh` still must not write it.
- Same-Round patch for submit/complete/interrupt. Span closeout is still a **new** Round written by Claude.
- This repo gitignores `docs/superpowers/`. Plans live under `docs/design/`.
- Interrupt stubs (exact): Summary body `這輪意外中斷。`; Handoff `#### 現況` then `這輪沒有正常收尾。`
- Placeholder User Input when prompt is missing: `（無 prompt）`
- Truncation notice (exact): `（後略，已截斷至 4000 字）`
- Inner fence replacement (exact): `` ``` `` → `⟨fence⟩`
- User Input body is wrapped in a `text` fence.
- Compact retains `INTERRUPTED` like `IN_PROGRESS` / `BLOCKED`.
- `/pause` deletes `.round-open` and `.interrupted` without rewriting the skeleton.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/close-open-round.sh` | Patch last Round to `INTERRUPTED` when `.round-open` matches; always exit 0 |
| `hooks/scripts/test-close-open-round.sh` | Helper self-check |
| `hooks/scripts/round-start.sh` | Dangling heal, skeleton append (unless well-formed span), hash after write, existing span/checkpoint/segment |
| `hooks/scripts/test-round-start.sh` | Submit-time skeleton self-check |
| `hooks/scripts/enforce-devlog.sh` | `.interrupted` short-circuit, then existing hash/headings; delete `.round-open` on success |
| `hooks/scripts/test-enforce-devlog.sh` | Existing cases plus interrupt / `.round-open` deletion |
| `hooks/scripts/on-stop-failure.sh` | Skip usage errors; else close-open |
| `hooks/scripts/on-session-end.sh` | Close-open with `SessionEnd:<reason>` |
| `hooks/scripts/on-tool-failure.sh` | Touch `.interrupted` when `is_interrupt` |
| `hooks/scripts/test-on-interrupt.sh` | The three wrappers |
| `hooks/scripts/session-start-devlog.sh` | Heal then existing inject |
| `hooks/scripts/test-session-start-devlog.sh` | Dangling heal on start |
| `hooks/scripts/test-segment-watch.sh` | Scenario 13 expects post-skeleton cksum |
| `hooks/hooks.json` | Register StopFailure / SessionEnd / PostToolUseFailure |
| `skills/devlog-tracker/SKILL.md` | Same-Round edit, `INTERRUPTED`, timing |
| `commands/start.md` | Submit-time skeleton |
| `commands/pause.md` | Delete the two new markers |
| `commands/compact.md` | Retain `INTERRUPTED` |
| `README.md` | Three moments + tree |
| `docs/design/segment-watch.md` | Authoring exception |
| `docs/design/summary-handoff.md` | Four-value Status |

Do not modify `hooks/scripts/segment-watch.sh`. Do not add a compact implementation script.

---

### Task 1: Shared `INTERRUPTED` patch

**Files:**
- Create: `hooks/scripts/test-close-open-round.sh`
- Create: `hooks/scripts/close-open-round.sh`
- Test: `bash hooks/scripts/test-close-open-round.sh`

**Interfaces:**
- Consumes: `$1` reason string; `CLAUDE_PROJECT_DIR`; `.enabled`; `.round-open` JSON field `round`; `.devlog/devlog.md`.
- Produces: always `exit 0`. On match: last Round Status becomes `INTERRUPTED` plus the reason line; missing Summary/Handoff stubs as in Global Constraints; deletes `.round-open` and `.interrupted`. On mismatch/malformed marker/missing files: deletes the markers, does not change Round bodies.

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-close-open-round.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Self-check for close-open-round.sh. Run:
#   bash hooks/scripts/test-close-open-round.sh
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
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (missing: $needle)"; FAIL=1 ;;
  esac
}
assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $desc (unexpected: $needle)"; FAIL=1 ;;
    *) echo "PASS: $desc" ;;
  esac
}

write_skeleton() {
  cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello
```

### Status
IN_PROGRESS
EOF
  printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
}

# --- 1: no .enabled -> no-op, file unchanged --------------------------------
rm -f "$DEVLOG_DIR/.enabled"
write_skeleton
BEFORE="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "dangling:next_prompt"
assert_exit "no .enabled -> exit 0" 0 $?
AFTER="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: no .enabled -> devlog.md unchanged"
else
  echo "FAIL: no .enabled should not edit devlog.md"
  FAIL=1
fi
touch "$DEVLOG_DIR/.enabled"

# --- 2: matching skeleton -> INTERRUPTED + stubs + markers gone -------------
write_skeleton
touch "$DEVLOG_DIR/.interrupted"
bash "$SCRIPT_DIR/close-open-round.sh" "StopFailure:server_error"
assert_exit "matching open round -> exit 0" 0 $?
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "status INTERRUPTED" $'### Status\nINTERRUPTED' "$BODY"
assert_contains "reason line" "StopFailure:server_error" "$BODY"
assert_contains "summary stub" "這輪意外中斷。" "$BODY"
assert_contains "handoff stub heading" "#### 現況" "$BODY"
assert_contains "handoff stub body" "這輪沒有正常收尾。" "$BODY"
assert_contains "user input kept" "hello" "$BODY"
if [ -f "$DEVLOG_DIR/.round-open" ] || [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: markers should be deleted after a successful stamp"
  FAIL=1
else
  echo "PASS: .round-open and .interrupted deleted"
fi

# --- 3: already has headings -> do not duplicate stubs, still stamp ---------
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello
```

### Summary
partial

### Handoff
#### 現況
partial

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "kept existing summary" "partial" "$BODY"
COUNT="$(printf '%s\n' "$BODY" | grep -c '^### Summary' || true)"
if [ "$COUNT" = "1" ]; then
  echo "PASS: did not add a second ### Summary"
else
  echo "FAIL: expected one ### Summary, got $COUNT"
  FAIL=1
fi
assert_contains "stamped interrupt" "INTERRUPTED" "$BODY"
assert_contains "user_interrupt reason" "user_interrupt" "$BODY"

# --- 4: wrong round in marker -> delete marker, do not edit -----------------
write_skeleton
printf '%s\n' '{"round": 99, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
BEFORE="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "dangling:session_start"
AFTER="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: mismatched round -> file unchanged"
else
  echo "FAIL: mismatched round edited the wrong Round"
  FAIL=1
fi
assert_not_contains "mismatch must not stamp" "INTERRUPTED" "$AFTER"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: mismatched marker should still be deleted"
  FAIL=1
else
  echo "PASS: mismatched .round-open deleted"
fi

# --- 5: no .round-open -> no-op --------------------------------------------
write_skeleton
rm -f "$DEVLOG_DIR/.round-open"
BEFORE="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:other"
AFTER="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: missing .round-open -> unchanged"
else
  echo "FAIL: missing .round-open edited the file"
  FAIL=1
fi

# --- 6: last Round after a Checkpoint; only last Round is patched -----------
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T11:00:00+08:00

### Summary
old

### Handoff
#### 現況
old

### Status
DONE

## Round 2 — 2026-09-09T12:00:00+08:00

### User Input
```text
new
```

### Status
IN_PROGRESS

## Checkpoint（Round 1-2 摘要）
keep me
EOF
printf '%s\n' '{"round": 2, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:clear"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "round 1 stays DONE" $'### Status\nDONE' "$BODY"
assert_contains "round 2 interrupted" "INTERRUPTED" "$BODY"
assert_contains "checkpoint kept" "keep me" "$BODY"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/test-close-open-round.sh`

Expected: FAIL because `close-open-round.sh` does not exist (`No such file or directory`), or the first `assert_exit` fails.

- [ ] **Step 3: Write the helper**

Create `hooks/scripts/close-open-round.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Stamp the open Round as INTERRUPTED. Always exit 0 (fail-open).
# Usage: close-open-round.sh <reason>
set -uo pipefail

REASON="${1:-unknown}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
INTERRUPTED_FLAG="$DEVLOG_DIR/.interrupted"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"

drop_markers() {
  rm -f "$ROUND_OPEN" "$INTERRUPTED_FLAG" 2>/dev/null || true
}

[ -f "$ENABLED_FLAG" ] || exit 0
[ -f "$ROUND_OPEN" ] || exit 0

OPEN_ROUND="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$ROUND_OPEN" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
case "$OPEN_ROUND" in
  ''|*[!0-9]*) drop_markers; exit 0 ;;
esac

if [ ! -f "$DEVLOG_FILE" ]; then
  drop_markers
  exit 0
fi

TMP="$DEVLOG_FILE.tmp"
awk -v want="$OPEN_ROUND" -v reason="$REASON" '
  /^[ \t]*```/ { fence = !fence }
  !fence && /^## Round / { last_start = NR }
  { lines[NR] = $0; infence[NR] = fence; n = NR }
  END {
    if (last_start == 0) { exit 2 }
    last_end = n
    for (i = last_start + 1; i <= n; i++) {
      if (!infence[i] && lines[i] ~ /^## /) { last_end = i - 1; break }
    }
    split(lines[last_start], parts, /[ \t]+/)
    rn = parts[3] + 0
    if (rn != want + 0) { exit 2 }

    has_s = 0
    has_h = 0
    for (i = last_start; i <= last_end; i++) {
      if (lines[i] ~ /^### Summary/) has_s = 1
      if (lines[i] ~ /^### Handoff/) has_h = 1
    }

    skip_val = 0
    saw_status = 0
    for (i = 1; i <= n; i++) {
      if (i < last_start || i > last_end) { print lines[i]; continue }
      if (skip_val) { skip_val = 0; continue }
      if (lines[i] ~ /^### Status/) {
        saw_status = 1
        if (!has_s) {
          print "### Summary"
          print "這輪意外中斷。"
          print ""
        }
        if (!has_h) {
          print "### Handoff"
          print "#### 現況"
          print "這輪沒有正常收尾。"
          print ""
        }
        print "### Status"
        print "INTERRUPTED"
        print reason
        skip_val = 1
        continue
      }
      print lines[i]
    }
    if (!saw_status) {
      if (!has_s) {
        print "### Summary"
        print "這輪意外中斷。"
        print ""
      }
      if (!has_h) {
        print "### Handoff"
        print "#### 現況"
        print "這輪沒有正常收尾。"
        print ""
      }
      print "### Status"
      print "INTERRUPTED"
      print reason
    }
  }
' "$DEVLOG_FILE" > "$TMP" 2>/dev/null
AWK_RC=$?
if [ "$AWK_RC" -eq 0 ]; then
  mv "$TMP" "$DEVLOG_FILE" 2>/dev/null || true
else
  rm -f "$TMP" 2>/dev/null || true
fi
drop_markers
exit 0
```

- [ ] **Step 4: Run the self-check**

Run: `bash hooks/scripts/test-close-open-round.sh`

Expected: `All checks passed.` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/close-open-round.sh hooks/scripts/test-close-open-round.sh
git commit -m "$(cat <<'EOF'
Add a shared helper that stamps an open Round as INTERRUPTED.

EOF
)"
```

---

### Task 2: Submit-time skeleton in `round-start.sh`

**Files:**
- Create: `hooks/scripts/test-round-start.sh`
- Modify: `hooks/scripts/round-start.sh`
- Modify: `hooks/scripts/test-segment-watch.sh` (Scenario 13 only)
- Test: `bash hooks/scripts/test-round-start.sh` and `bash hooks/scripts/test-segment-watch.sh`

**Interfaces:**
- Consumes: `close-open-round.sh` with reason `dangling:next_prompt`; UserPromptSubmit stdin `prompt`; well-formed `.span-open` (`ticks_since_checkin` and `max_silent_ticks` both numeric) as the skip-new-Round signal.
- Produces: unless skipped, appends `## Round N` skeleton (fenced User Input, `Status IN_PROGRESS`), writes `.round-open`, writes `.turn-start` **after** that write; then existing span tick / checkpoint / segment-reset. Span skip: no new Round, no `.round-open`.

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-round-start.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Self-check for round-start.sh skeleton + dangling heal. Run:
#   bash hooks/scripts/test-round-start.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"

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
assert_file_absent() {
  local desc="$1" path="$2"
  if [ -e "$path" ]; then
    echo "FAIL: $desc ($path exists)"
    FAIL=1
  else
    echo "PASS: $desc"
  fi
}

PROMPT_HELLO='{"prompt":"hello world"}'

# --- 1: disabled -> no files ----------------------------------------------
printf '%s' "$PROMPT_HELLO" | bash "$SCRIPT_DIR/round-start.sh"
assert_exit "disabled -> exit 0" 0 $?
assert_file_absent "disabled -> no devlog.md" "$DEVLOG_DIR/devlog.md"
assert_file_absent "disabled -> no .round-open" "$DEVLOG_DIR/.round-open"
assert_file_absent "disabled -> no .turn-start" "$DEVLOG_DIR/.turn-start"

touch "$DEVLOG_DIR/.enabled"

# --- 2: Round 1 skeleton + markers + hash after write ---------------------
printf '%s' "$PROMPT_HELLO" | bash "$SCRIPT_DIR/round-start.sh"
assert_exit "first prompt -> exit 0" 0 $?
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "Round 1 heading" "## Round 1 —" "$BODY"
assert_contains "fenced user input" $'```text\nhello world\n```' "$BODY"
assert_contains "status in progress" $'### Status\nIN_PROGRESS' "$BODY"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "PASS: .round-open created"
else
  echo "FAIL: .round-open missing"
  FAIL=1
fi
OPEN_N="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.round-open" | grep -o '[0-9]\+$')"
if [ "$OPEN_N" = "1" ]; then
  echo "PASS: .round-open round=1"
else
  echo "FAIL: .round-open round should be 1, got $OPEN_N"
  FAIL=1
fi
AFTER_HASH="$(cksum < "$DEVLOG_DIR/devlog.md")"
START_HASH="$(cat "$DEVLOG_DIR/.turn-start")"
if [ "$AFTER_HASH" = "$START_HASH" ]; then
  echo "PASS: .turn-start matches post-skeleton hash"
else
  echo "FAIL: .turn-start should be captured after skeleton write"
  FAIL=1
fi

# --- 3: next prompt is Round 2 --------------------------------------------
printf '%s' '{"prompt":"second"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "Round 2 heading" "## Round 2 —" "$BODY"
assert_contains "previous round interrupted (dangling heal)" "INTERRUPTED" "$BODY"
assert_contains "dangling reason" "dangling:next_prompt" "$BODY"
OPEN_N="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.round-open" | grep -o '[0-9]\+$')"
if [ "$OPEN_N" = "2" ]; then
  echo "PASS: .round-open now round=2"
else
  echo "FAIL: .round-open round should be 2, got $OPEN_N"
  FAIL=1
fi

# --- 4: checkpoint increments once on dangling+new ------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start"
printf '%s\n' '{"rounds_since_checkpoint": 0, "max_silent_rounds": 20, "checkpoint_marker_count": 0}' > "$DEVLOG_DIR/.checkpoint-state"
printf '%s' "$PROMPT_HELLO" | bash "$SCRIPT_DIR/round-start.sh"
printf '%s' '{"prompt":"again"}' | bash "$SCRIPT_DIR/round-start.sh"
CP="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP" = "2" ]; then
  echo "PASS: two UserPromptSubmit ticks -> rounds_since_checkpoint=2 (dangling+new still one increment each)"
else
  echo "FAIL: expected rounds_since_checkpoint=2, got $CP"
  FAIL=1
fi

# --- 5: well-formed span skips new Round, still increments ticks ----------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
: > "$DEVLOG_DIR/devlog.md"
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 9,
  "opened_at": "2026-09-09T00:00:00+08:00",
  "ticks_since_checkin": 0,
  "max_silent_ticks": 5
}
SPANEOF
printf '%s' "$PROMPT_HELLO" | bash "$SCRIPT_DIR/round-start.sh"
if grep -q '## Round' "$DEVLOG_DIR/devlog.md"; then
  echo "FAIL: span tick should not append a Round"
  FAIL=1
else
  echo "PASS: span tick appended no Round"
fi
assert_file_absent "span tick -> no .round-open" "$DEVLOG_DIR/.round-open"
TICKS="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.span-open" | grep -o '[0-9]\+$')"
if [ "$TICKS" = "1" ]; then
  echo "PASS: span ticks incremented to 1"
else
  echo "FAIL: ticks_since_checkin should be 1, got $TICKS"
  FAIL=1
fi
rm -f "$DEVLOG_DIR/.span-open"

# --- 6: missing prompt -> placeholder -------------------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
printf '%s' '{}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "placeholder prompt" "（無 prompt）" "$BODY"

# --- 7a: inner fence neutralized before wrapping ----------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
printf '%s' '{"prompt":"before```inside```after"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "inner fence neutralized" "⟨fence⟩" "$BODY"
if printf '%s\n' "$BODY" | grep -q '```inside'; then
  echo "FAIL: raw inner fence leaked into the wrapper"
  FAIL=1
else
  echo "PASS: wrapper fence stayed closed"
fi

# --- 7b: truncation notice when prompt exceeds 4000 -------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
LONG="$(awk 'BEGIN { s=""; for (i=0;i<4005;i++) s=s "a"; print s }')"
printf '{"prompt":"%s"}' "$LONG" | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "truncation notice" "（後略，已截斷至 4000 字）" "$BODY"
LEN="$(awk '/^```text$/{p=1;next} /^```$/{p=0;next} p{s=s $0} END{print length(s)}' "$DEVLOG_DIR/devlog.md")"
if [ "$LEN" -le 4000 ]; then
  echo "PASS: fenced body length <= 4000 (got $LEN)"
else
  echo "FAIL: fenced body length $LEN exceeds 4000"
  FAIL=1
fi

# --- 8: heading injection stays inside fence --------------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
printf '%s' '{"prompt":"see\n## Round 99\n### Status"}' | bash "$SCRIPT_DIR/round-start.sh"
# Only one unfenced ## Round (the real heading). Count fence-aware:
UNFENCED="$(awk '/^[ \t]*```/{f=!f} !f && /^## Round /{c++} END{print c+0}' "$DEVLOG_DIR/devlog.md")"
if [ "$UNFENCED" = "1" ]; then
  echo "PASS: prompt ## Round 99 did not create a second unfenced Round heading"
else
  echo "FAIL: expected 1 unfenced ## Round heading, got $UNFENCED"
  FAIL=1
fi

# --- 9: segment last_seen_cksum is post-skeleton ----------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
printf '%s\n' '{"last_change_epoch": 1, "last_seen_cksum": "old", "max_silent_seconds": 900}' > "$DEVLOG_DIR/.segment-state"
printf '%s' "$PROMPT_HELLO" | bash "$SCRIPT_DIR/round-start.sh"
POST="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"
SEEN="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
if [ "$SEEN" = "$POST" ]; then
  echo "PASS: segment last_seen_cksum matches post-skeleton hash"
else
  echo "FAIL: last_seen_cksum=$SEEN expected $POST"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/test-round-start.sh`

Expected: FAIL on “first prompt” (no skeleton / no `.round-open`).

- [ ] **Step 3: Implement skeleton + dangling heal in `round-start.sh`**

Replace `hooks/scripts/round-start.sh` with this exact content:

```bash
#!/usr/bin/env bash
# UserPromptSubmit hook：每次使用者送出新訊息時執行。
# 互動輪次：先（如有）把上一輪未收尾標成 INTERRUPTED，再追加本輪 User Input
# skeleton，然後把 .turn-start 設成「寫完 skeleton 之後」的雜湊，供 Stop hook
# 判斷 Claude 有沒有再寫 Summary/Handoff。
# Span 開著且檔案格式有效時不開新 Round。
# fail-open：這支腳本本身出任何問題都不該影響使用者送出訊息，一律 exit 0。

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
SPAN_FILE="$DEVLOG_DIR/.span-open"
CHECKPOINT_FILE="$DEVLOG_DIR/.checkpoint-state"
SEGMENT_FILE="$DEVLOG_DIR/.segment-state"
ROUND_OPEN="$DEVLOG_DIR/.round-open"

[ -f "$ENABLED_FLAG" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"

if [ -f "$ROUND_OPEN" ]; then
  bash "$HOOKS_DIR/close-open-round.sh" "dangling:next_prompt" || true
fi

SPAN_SKIP=0
if [ -f "$SPAN_FILE" ]; then
  SPAN_TICKS="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$SPAN_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  SPAN_MAX="$(grep -o '"max_silent_ticks"[[:space:]]*:[[:space:]]*[0-9]\+' "$SPAN_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  case "$SPAN_TICKS" in ''|*[!0-9]*) SPAN_TICKS='' ;; esac
  case "$SPAN_MAX" in ''|*[!0-9]*) SPAN_MAX='' ;; esac
  if [ -n "$SPAN_TICKS" ] && [ -n "$SPAN_MAX" ]; then
    SPAN_SKIP=1
  fi
fi

PROMPT=""
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo '')"
  if [ "$PROMPT" = "null" ]; then PROMPT=""; fi
else
  PROMPT="$(printf '%s' "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi

if [ "$SPAN_SKIP" -eq 0 ]; then
  if [ -z "$PROMPT" ]; then
    PROMPT="（無 prompt）"
  fi
  TRUNC_NOTE=""
  if [ "${#PROMPT}" -gt 4000 ]; then
    PROMPT="${PROMPT:0:4000}"
    TRUNC_NOTE="（後略，已截斷至 4000 字）"
  fi
  PROMPT="$(printf '%s' "$PROMPT" | sed 's/```/⟨fence⟩/g')"

  LAST_N=0
  if [ -f "$DEVLOG_FILE" ]; then
    LAST_N="$(awk '
      /^[ \t]*```/ { fence = !fence }
      !fence && /^## Round / {
        split($0, parts, /[ \t]+/)
        n = parts[3] + 0
        if (n > last) last = n
      }
      END { print last + 0 }
    ' "$DEVLOG_FILE" 2>/dev/null || echo 0)"
    case "$LAST_N" in ''|*[!0-9]*) LAST_N=0 ;; esac
  fi
  NEXT_N=$((LAST_N + 1))
  TS="$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo unknown)"

  {
    printf '\n## Round %s — %s\n\n' "$NEXT_N" "$TS"
    printf '### User Input\n'
    printf '```text\n'
    printf '%s\n' "$PROMPT"
    printf '```\n'
    if [ -n "$TRUNC_NOTE" ]; then
      printf '%s\n' "$TRUNC_NOTE"
    fi
    printf '\n### Status\nIN_PROGRESS\n'
  } >> "$DEVLOG_FILE" 2>/dev/null || true

  if [ -f "$DEVLOG_FILE" ]; then
    printf '{"round": %s, "opened_at": "%s"}\n' "$NEXT_N" "$TS" > "$ROUND_OPEN" 2>/dev/null || true
  fi
fi

if [ -f "$DEVLOG_FILE" ]; then
  cksum < "$DEVLOG_FILE" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
else
  echo "MISSING" > "$DEVLOG_DIR/.turn-start" 2>/dev/null || true
fi

SPAN_WILL_PASS_THROUGH=0
if [ -f "$SPAN_FILE" ]; then
  SPAN_TICKS="$(grep -o '"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]\+' "$SPAN_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  SPAN_MAX="$(grep -o '"max_silent_ticks"[[:space:]]*:[[:space:]]*[0-9]\+' "$SPAN_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  case "$SPAN_TICKS" in ''|*[!0-9]*) SPAN_TICKS='' ;; esac
  case "$SPAN_MAX" in ''|*[!0-9]*) SPAN_MAX='' ;; esac
  if [ -n "$SPAN_TICKS" ]; then
    NEW_TICKS=$((SPAN_TICKS + 1))
    awk -v new="$NEW_TICKS" '{ gsub(/"ticks_since_checkin"[[:space:]]*:[[:space:]]*[0-9]+/, "\"ticks_since_checkin\": " new); print }' "$SPAN_FILE" > "$SPAN_FILE.tmp" 2>/dev/null \
      && mv "$SPAN_FILE.tmp" "$SPAN_FILE" 2>/dev/null || true
    if [ -n "$SPAN_MAX" ] && [ "$NEW_TICKS" -lt "$SPAN_MAX" ]; then
      SPAN_WILL_PASS_THROUGH=1
    fi
  fi
fi

if [ "$SPAN_WILL_PASS_THROUGH" -eq 0 ] && [ -f "$CHECKPOINT_FILE" ]; then
  CP_ROUNDS="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$CHECKPOINT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  case "$CP_ROUNDS" in
    ''|*[!0-9]*) : ;;
    *)
      NEW_CP_ROUNDS=$((CP_ROUNDS + 1))
      awk -v new="$NEW_CP_ROUNDS" '{ gsub(/"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]+/, "\"rounds_since_checkpoint\": " new); print }' "$CHECKPOINT_FILE" > "$CHECKPOINT_FILE.tmp" 2>/dev/null \
        && mv "$CHECKPOINT_FILE.tmp" "$CHECKPOINT_FILE" 2>/dev/null || true
      ;;
  esac
fi

if [ -f "$SEGMENT_FILE" ]; then
  SEG_EPOCH="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  SEG_MAX="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$SEGMENT_FILE" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  SEG_SUM_KEY="$(grep -o '"last_seen_cksum"[[:space:]]*:' "$SEGMENT_FILE" 2>/dev/null || echo '')"
  case "$SEG_EPOCH" in ''|*[!0-9]*) SEG_EPOCH='' ;; esac
  case "$SEG_MAX" in ''|*[!0-9]*) SEG_MAX='' ;; esac
  if [ -n "$SEG_EPOCH" ] && [ -n "$SEG_MAX" ] && [ -n "$SEG_SUM_KEY" ]; then
    SEG_NOW="$(date +%s 2>/dev/null || echo '')"
    case "$SEG_NOW" in
      ''|*[!0-9]*) : ;;
      *)
        if [ -f "$DEVLOG_FILE" ]; then
          SEG_CUR="$(cksum < "$DEVLOG_FILE" 2>/dev/null | tr -d '\n' || echo '')"
        else
          SEG_CUR="MISSING"
        fi
        if [ -n "$SEG_CUR" ]; then
          awk -v epoch="$SEG_NOW" -v sum="$SEG_CUR" '{
            gsub(/"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]+/, "\"last_change_epoch\": " epoch);
            gsub(/"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"last_seen_cksum\": \"" sum "\"");
            print
          }' "$SEGMENT_FILE" > "$SEGMENT_FILE.tmp" 2>/dev/null \
            && mv "$SEGMENT_FILE.tmp" "$SEGMENT_FILE" 2>/dev/null || true
        fi
        ;;
    esac
  fi
fi

exit 0
```

- [ ] **Step 4: Fix Segment Watch Scenario 13 to the post-skeleton hash**

In `hooks/scripts/test-segment-watch.sh`, replace the Scenario 13 assertion block (the `if [ "$RS_EPOCH" -ge "$NOW" ] && [ "$RS_SUM" = "$SEED_CKSUM" ]` condition and its FAIL message) with:

```bash
# --- Scenario 13: round-start.sh resets clock and preserves max -------------
write_state 1 "old-sum" 600
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
POST_SKEL="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"
RS_EPOCH="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
RS_SUM="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
RS_MAX="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
if [ "$RS_EPOCH" -ge "$NOW" ] && [ "$RS_SUM" = "$POST_SKEL" ] && [ "$RS_MAX" = "600" ]; then
  echo "PASS: round-start.sh reset epoch/cksum to post-skeleton hash and kept max_silent_seconds=600"
else
  echo "FAIL: round-start expected epoch>=$NOW cksum=$POST_SKEL max=600, got epoch=$RS_EPOCH cksum=$RS_SUM max=$RS_MAX"
  FAIL=1
fi
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "immediately after round-start.sh, Bash -> allowed" 0 $?
```

Leave the `write_state 1 "old-sum" 600` / `round-start` / following Bash assert as one contiguous Scenario 13 (delete the old `RS_SUM = "$SEED_CKSUM"` version so it is not duplicated).

- [ ] **Step 5: Run the new and existing self-checks**

Run:

```bash
bash hooks/scripts/test-round-start.sh
bash hooks/scripts/test-segment-watch.sh
bash hooks/scripts/test-close-open-round.sh
bash hooks/scripts/test-enforce-devlog.sh
```

Expected: first three print `All checks passed.`

`test-enforce-devlog.sh` should still pass scenarios 1–3: `round-start` now writes a skeleton then snapshots that hash, so Stop with no further edit still exits 2. If anything fails because a later heading scenario now has an extra skeleton Round in the way, do **not** rewrite those fixtures in this task — that belongs to Task 3 only if a failure is a real hash/heading break. If Task 2 leaves `test-enforce-devlog.sh` red solely due to leftover `.round-open` / extra skeletons making “last Round” the skeleton, stop and fix `test-enforce-devlog.sh` in Task 3 before committing this task… **except** if the only failures are heading scenarios that `cat >` overwrite the file after `round-start` (those still set last Round explicitly and should stay green).

If `test-enforce-devlog.sh` is green, proceed to commit.

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/round-start.sh hooks/scripts/test-round-start.sh hooks/scripts/test-segment-watch.sh
git commit -m "$(cat <<'EOF'
Write a Round skeleton at UserPromptSubmit and snapshot the hash after it.

EOF
)"
```

---

### Task 3: Stop hook — interrupt short-circuit and `.round-open` cleanup

**Files:**
- Modify: `hooks/scripts/enforce-devlog.sh`
- Modify: `hooks/scripts/test-enforce-devlog.sh` (append scenarios at the end, before the final `FAIL` summary)
- Test: `bash hooks/scripts/test-enforce-devlog.sh`

**Interfaces:**
- Consumes: `close-open-round.sh` reason `user_interrupt` when `.interrupted` exists; `.round-open` on successful close.
- Produces: if `.interrupted` → stamp and `exit 0` **before** loop guard. Heading miss → do not delete `.round-open`, do not reset span ticks (already true). Hash+headings pass → `rm -f .round-open` then existing span reset / checkpoint.

- [ ] **Step 1: Append the failing cases to `test-enforce-devlog.sh`**

Immediately before the final `if [ "$FAIL" -eq 0 ]; then` block, insert:

```bash
# --- Recording moments: skeleton hash-equal still blocks -------------------
rm -f "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.checkpoint-state" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.interrupted"
: > "$DEVLOG_DIR/devlog.md"
printf '%s' '{"prompt":"block me"}' | bash "$SCRIPT_DIR/round-start.sh"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "skeleton only (hash equal after submit write) -> blocked" 2 $?
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "PASS: .round-open remains after hash-miss block"
else
  echo "FAIL: .round-open should remain when Stop blocks"
  FAIL=1
fi

# --- Recording moments: Summary+Handoff on same Round deletes .round-open --
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
block me
```

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/devlog.md" > "$DEVLOG_DIR/.turn-start"
# Hash equal would block — simulate Claude's edit by appending a newline after snapshot:
printf '\n' >> "$DEVLOG_DIR/devlog.md"
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "headings present and hash changed -> allowed" 0 $?
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: .round-open should be deleted on successful Stop"
  FAIL=1
else
  echo "PASS: .round-open deleted after successful close"
fi

# --- Recording moments: .interrupted stamps and does not block -------------
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
esc
```

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/devlog.md" > "$DEVLOG_DIR/.turn-start"
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
if [ -f "$DEVLOG_DIR/.interrupted" ] || [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: interrupt path should delete both markers"
  FAIL=1
else
  echo "PASS: interrupt path deleted markers"
fi

# --- Recording moments: loop guard leaves .round-open ----------------------
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

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
```

- [ ] **Step 2: Run to verify the new cases fail**

Run: `bash hooks/scripts/test-enforce-devlog.sh`

Expected: FAIL on `.interrupted -> exit 0` and/or `.round-open should be deleted` (current Stop does not stamp or delete the marker).

- [ ] **Step 3: Patch `enforce-devlog.sh`**

1. Immediately after `set -uo pipefail`, add:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

2. After `INPUT="$(cat 2>/dev/null || true)"` and **before** the `jq` loop-guard parse, insert:

```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt" || true
  exit 0
fi
```

3. Remove the later duplicate `PROJECT_DIR=...` / `DEVLOG_DIR=...` assignments under `開關檢查`, but **keep** `ENABLED_FLAG`, `TURN_MARKER`, and `DEVLOG_FILE` there (they can stay as-is under 開關檢查). If you already set `PROJECT_DIR`/`DEVLOG_DIR` above, do not assign them a second time; reuse the same variables.

4. After the heading-check `if` block succeeds (the block that currently ends just before the span tick reset comment `這輪真的有寫東西`), insert:

```bash
rm -f "$DEVLOG_DIR/.round-open" 2>/dev/null || true
```

Do not put that `rm` on the heading-miss `exit 2` path. Do not put it on the hash-miss `exit 2` path.

- [ ] **Step 4: Run**

Run: `bash hooks/scripts/test-enforce-devlog.sh`

Expected: `All checks passed.`

Also run: `bash hooks/scripts/test-round-start.sh` — still green.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/enforce-devlog.sh hooks/scripts/test-enforce-devlog.sh
git commit -m "$(cat <<'EOF'
Honor Esc via .interrupted and drop .round-open on a successful Stop.

EOF
)"
```

---

### Task 4: StopFailure, SessionEnd, PostToolUseFailure wrappers

**Files:**
- Create: `hooks/scripts/on-stop-failure.sh`
- Create: `hooks/scripts/on-session-end.sh`
- Create: `hooks/scripts/on-tool-failure.sh`
- Create: `hooks/scripts/test-on-interrupt.sh`
- Test: `bash hooks/scripts/test-on-interrupt.sh`

**Interfaces:**
- Consumes: `close-open-round.sh`; StopFailure stdin `error`; SessionEnd stdin `reason`; PostToolUseFailure stdin `is_interrupt`.
- Produces: usage errors no-op; other StopFailure → `StopFailure:<error>` (missing error → `StopFailure:unknown`); SessionEnd → `SessionEnd:<reason>` (missing → `SessionEnd:other`); `is_interrupt` true → create `.interrupted` only (no `devlog.md` edit). All wrappers `exit 0`.

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-on-interrupt.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Self-check for on-stop-failure.sh / on-session-end.sh / on-tool-failure.sh.
# Run: bash hooks/scripts/test-on-interrupt.sh
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

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash hooks/scripts/test-on-interrupt.sh`

Expected: FAIL (`on-stop-failure.sh` missing).

- [ ] **Step 3: Write the three wrappers**

`hooks/scripts/on-stop-failure.sh`:

```bash
#!/usr/bin/env bash
# StopFailure: stamp INTERRUPTED unless this is a usage-exhaustion error.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat 2>/dev/null || true)"

ERROR=""
if command -v jq >/dev/null 2>&1; then
  ERROR="$(printf '%s' "$INPUT" | jq -r '.error // empty' 2>/dev/null || echo '')"
  if [ "$ERROR" = "null" ]; then ERROR=""; fi
else
  ERROR="$(printf '%s' "$INPUT" | grep -o '"error"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi

case "$ERROR" in
  rate_limit|billing_error|account_on_hold) exit 0 ;;
  '') ERROR="unknown" ;;
esac

bash "$HOOKS_DIR/close-open-round.sh" "StopFailure:${ERROR}" || true
exit 0
```

`hooks/scripts/on-session-end.sh`:

```bash
#!/usr/bin/env bash
# SessionEnd: stamp INTERRUPTED if a Round is still open.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat 2>/dev/null || true)"

REASON=""
if command -v jq >/dev/null 2>&1; then
  REASON="$(printf '%s' "$INPUT" | jq -r '.reason // empty' 2>/dev/null || echo '')"
  if [ "$REASON" = "null" ]; then REASON=""; fi
else
  REASON="$(printf '%s' "$INPUT" | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi
[ -n "$REASON" ] || REASON="other"

bash "$HOOKS_DIR/close-open-round.sh" "SessionEnd:${REASON}" || true
exit 0
```

`hooks/scripts/on-tool-failure.sh`:

```bash
#!/usr/bin/env bash
# PostToolUseFailure: remember user Esc so Stop can stamp without blocking.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
[ -f "$ENABLED_FLAG" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
IS_INT="false"
if command -v jq >/dev/null 2>&1; then
  IS_INT="$(printf '%s' "$INPUT" | jq -r '.is_interrupt // false' 2>/dev/null || echo false)"
else
  case "$INPUT" in
    *'"is_interrupt":true'*|*'"is_interrupt": true'*) IS_INT=true ;;
    *) IS_INT=false ;;
  esac
fi

if [ "$IS_INT" = "true" ]; then
  mkdir -p "$DEVLOG_DIR" 2>/dev/null || true
  : > "$DEVLOG_DIR/.interrupted" 2>/dev/null || true
fi
exit 0
```

- [ ] **Step 4: Run**

Run: `bash hooks/scripts/test-on-interrupt.sh`

Expected: `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/on-stop-failure.sh hooks/scripts/on-session-end.sh hooks/scripts/on-tool-failure.sh hooks/scripts/test-on-interrupt.sh
git commit -m "$(cat <<'EOF'
Stamp unexpected StopFailure and SessionEnd; remember Esc on tool failure.

EOF
)"
```

---

### Task 5: SessionStart dangling heal

**Files:**
- Modify: `hooks/scripts/session-start-devlog.sh`
- Modify: `hooks/scripts/test-session-start-devlog.sh`
- Test: `bash hooks/scripts/test-session-start-devlog.sh`

**Interfaces:**
- Consumes: `close-open-round.sh` reason `dangling:session_start` (no-op without `.enabled` / `.round-open`).
- Produces: heal first, then existing span warning + last-8-rounds excerpt. Heal must not print anything of its own. SessionStart still `exit 0` with no output when there is no `devlog.md` and no span.

- [ ] **Step 1: Add the failing case to `test-session-start-devlog.sh`**

After Scenario 4 (malformed span), before the final `FAIL` summary, insert:

```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash hooks/scripts/test-session-start-devlog.sh`

Expected: FAIL (`INTERRUPTED` missing).

- [ ] **Step 3: Heal at the top of `session-start-devlog.sh`**

After `set -uo pipefail` and the existing `PROJECT_DIR` / `DEVLOG_DIR` assignments, before the span-warning `if`, insert:

```bash
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  bash "$HOOKS_DIR/close-open-round.sh" "dangling:session_start" || true
fi
```

Do not change the last-8-rounds awk.

- [ ] **Step 4: Run**

Run: `bash hooks/scripts/test-session-start-devlog.sh`

Expected: `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/session-start-devlog.sh hooks/scripts/test-session-start-devlog.sh
git commit -m "$(cat <<'EOF'
Stamp a dangling open Round when a session starts so crash recovery has Status.

EOF
)"
```

---

### Task 6: Register the new hooks

**Files:**
- Modify: `hooks/hooks.json`

**Interfaces:**
- Consumes: the three wrapper scripts from Task 4.
- Produces: Claude Code events `StopFailure`, `SessionEnd`, `PostToolUseFailure` with no matchers (usage skip is in-script).

- [ ] **Step 1: There is no unit test for JSON shape — validate by reading the file after edit**

- [ ] **Step 2: Update `hooks/hooks.json` to this exact content**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/session-start-devlog.sh\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/round-start.sh\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/segment-watch.sh\""
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/on-tool-failure.sh\""
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/on-stop-failure.sh\""
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/on-session-end.sh\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/enforce-devlog.sh\""
          }
        ]
      }
    ]
  }
}
```

Keep `Stop` last in the file only for readability; event order in JSON is not execution order across types.

- [ ] **Step 3: Re-run the full hook self-check suite**

```bash
bash hooks/scripts/test-close-open-round.sh
bash hooks/scripts/test-round-start.sh
bash hooks/scripts/test-on-interrupt.sh
bash hooks/scripts/test-enforce-devlog.sh
bash hooks/scripts/test-session-start-devlog.sh
bash hooks/scripts/test-segment-watch.sh
```

Expected: all six print `All checks passed.`

- [ ] **Step 4: Commit**

```bash
git add hooks/hooks.json
git commit -m "$(cat <<'EOF'
Wire StopFailure, SessionEnd, and PostToolUseFailure into the plugin hooks.

EOF
)"
```

---

### Task 7: Authoring docs and related design notes

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md`
- Modify: `commands/start.md`
- Modify: `commands/pause.md`
- Modify: `commands/compact.md`
- Modify: `README.md`
- Modify: `docs/design/segment-watch.md`
- Modify: `docs/design/summary-handoff.md`

No new tests. After the edits, re-run the six `test-*.sh` scripts from Task 6 Step 3 to confirm docs-only changes did not touch hooks.

- [ ] **Step 1: SKILL.md — switch, format, Status, boundary**

Replace the numbered switch flow (the three steps that currently say hash-at-start / hash-at-stop / block) with:

```
1. 使用者送出新訊息時，`UserPromptSubmit` hook（`hooks/scripts/round-start.sh`）
   若開關開著，就在 `.devlog/devlog.md` 尾端追加這一輪的 skeleton（`### User Input`
   + `Status: IN_PROGRESS`），並寫 `.devlog/.round-open`。`.turn-start` 雜湊是
   **寫完 skeleton 之後**才拍的，所以 Stop 仍能判斷 Claude 有沒有再補收尾。
2. Claude 編輯**同一個** Round：不要再 append 一個新的 `## Round`。不要改 User Input
   （除非裡面是 hook 的 `（無 prompt）` 占位）。補上 `### Summary` / `### Handoff`，
   把 Status 改成 `DONE` / `IN_PROGRESS` / `BLOCKED`。
3. `Stop` hook（`hooks/scripts/enforce-devlog.sh`）若雜湊沒變、或最後一個 Round
   缺少 `### Summary` / `### Handoff`，就用 exit code 2 擋下來。通過則刪掉
   `.round-open`。
```

Replace Status line `DONE | IN_PROGRESS | BLOCKED` with:

```
DONE | IN_PROGRESS | BLOCKED | INTERRUPTED
```

Add immediately after the Status bullet that says Claude must not put next-steps under Status:

```
- `INTERRUPTED` 只由 hook 在意外中斷時寫上（Esc、非 usage 的 API 錯誤、SessionEnd、
  下次 SessionStart / 下一則訊息發現 `.round-open` 還在）。Claude 正常收尾時不要自己選這個值。
  usage 用光（`rate_limit` / `billing_error` / `account_on_hold`）不標中斷。
```

Replace the paragraph that currently says only a normally finished turn is guaranteed (the 「需要誠實說明的邊界」 block) with:

```
User Input 在送出當下就已經在 `devlog.md`。正常結束時 Stop 仍保證有 Summary / Handoff。
意外中斷會把同一塊標成 `INTERRUPTED`（process 被殺時，Status 要等下次 SessionStart 或
下一則訊息才補上）。中間沒寫成 `### 段落` 的過程仍會丟——Segment Watch 只在還有下一個
工具呼叫時催促。
```

In the Round format section that currently says 「完成一輪工作後（或使用者要求先記錄時），在檔案尾端新增」，change it to: hook 已在送出時寫好 User Input；Claude **編輯最後一個 Round**，不要為同一則使用者訊息再新增一個 `## Round`。

- [ ] **Step 2: Commands**

`commands/start.md`: in the closing user-facing sentence, mention that 每一則使用者訊息送出時就會先寫 User Input skeleton，結束前仍要補 Summary / Handoff。

`commands/pause.md`: after the `.span-open` delete step, add:

```
3. 如果 `.devlog/.round-open` 或 `.devlog/.interrupted` 存在也刪掉——暫停不是崩潰，
   不要讓下次 start 把當下的 skeleton 標成 INTERRUPTED。不要改 `devlog.md` 裡已寫的 Round。
```

Renumber the following “don't delete `.segment-state`” item to 4 and the user-facing inform item to 5.

`commands/compact.md` step 3 retain bullet: change `IN_PROGRESS` 或 `BLOCKED` to `IN_PROGRESS`、`BLOCKED` 或 `INTERRUPTED`.

- [ ] **Step 3: README**

- In 特色, add that UserPromptSubmit writes User Input immediately and unexpected interrupts become `INTERRUPTED` (not usage limits).
- Status list: add `INTERRUPTED`.
- Directory tree: add `recording-moments.md`, `close-open-round.sh`, `on-stop-failure.sh`, `on-session-end.sh`, `on-tool-failure.sh`, and the new `test-*.sh` files. Update the `hooks.json` comment to list StopFailure / SessionEnd / PostToolUseFailure.

- [ ] **Step 4: Design notes**

In `docs/design/segment-watch.md`, under **Do not author `devlog.md` from a hook.**, add:

```
Exception (see `docs/design/recording-moments.md`): `UserPromptSubmit` writes the
Round skeleton, and interrupt helpers patch Status to `INTERRUPTED`. Segment Watch
itself still only checks.
```

In `docs/design/summary-handoff.md`, change the Status enum to `DONE | IN_PROGRESS | BLOCKED | INTERRUPTED` and note `INTERRUPTED` is hook-only, not a Claude close choice. Do not require Summary/Handoff quality checks on interrupt stubs.

- [ ] **Step 5: Regression**

```bash
bash hooks/scripts/test-close-open-round.sh
bash hooks/scripts/test-round-start.sh
bash hooks/scripts/test-on-interrupt.sh
bash hooks/scripts/test-enforce-devlog.sh
bash hooks/scripts/test-session-start-devlog.sh
bash hooks/scripts/test-segment-watch.sh
```

Expected: all six `All checks passed.`

- [ ] **Step 6: Commit**

```bash
git add skills/devlog-tracker/SKILL.md commands/start.md commands/pause.md commands/compact.md README.md docs/design/segment-watch.md docs/design/summary-handoff.md
git commit -m "$(cat <<'EOF'
Document submit-time skeletons, INTERRUPTED, and the Segment Watch authoring exception.

EOF
)"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|---|---|
| Submit writes same-Round skeleton + `.round-open`; hash after write | 2 |
| Encoding: 4000, fence wrap, `⟨fence⟩`, `（無 prompt）` | 2 |
| Span well-formed skips new Round | 2 |
| Dangling heal on next prompt, checkpoint +1 per submit | 2 |
| Segment `last_seen_cksum` after skeleton | 2 |
| Stop: `.interrupted` before loop guard | 3 |
| Stop: hash + Summary/Handoff; no `.round-open` delete on miss | 3 |
| Stop success deletes `.round-open` | 3 |
| `close-open-round.sh` stubs + mismatch fail-open | 1 |
| Usage skip three errors; other StopFailure stamp | 4 |
| SessionEnd / PostToolUseFailure | 4 |
| SessionStart heal | 5 |
| `hooks.json` | 6 |
| Compact / pause / SKILL / README / design exceptions | 7 |
| `segment-watch.sh` unchanged | (no task) |
| No transcript parse, no version bump | (constraints) |
