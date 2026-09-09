# Reply Fold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Claude ends a turn on a plain-text clarifying question and marks that intent, fold the user's next message into the same Round as a `### 段落` block instead of opening a new `## Round`.

**Architecture:** A new one-shot marker file `.devlog/.awaiting-reply` (written by a new `await-open.sh`, modeled on `span-open.sh`) records which Round is waiting for a reply. `round-start.sh` reads and always consumes it on the next `UserPromptSubmit`: if its `round` still matches the file's last `## Round`, the incoming prompt is inserted as a new `### 段落` block right before that Round's `### Summary` line (fence-aware, via `devlog-md.sh` helpers) instead of appending a new `## Round`; `.round-open` is rewritten to point at that same Round so interrupt-healing still works. If it doesn't match, the marker is dropped and the normal new-Round path runs unchanged. `enforce-devlog.sh` and `close-open-round.sh` need no changes — both already operate on "whatever the last `## Round` is."

**Tech Stack:** bash hooks, existing sourced helpers `json-field.sh` (`json_int_get`), `devlog-md.sh` (`devlog_list_round_starts`, `devlog_block_end`), `devlog-lock.sh` (`devlog_lock_acquire`/`devlog_lock_release`), `redact-prompt.sh` (`redact_prompt`); `awk`/`sed`/`cksum`/`date`; assert-and-exit self-checks under `hooks/scripts/test-*.sh`, auto-discovered by `hooks/scripts/run-tests.sh`.

**Spec:** `docs/design/reply-fold.md`

## Global Constraints

- `.awaiting-reply` is a one-shot marker: `round-start.sh` deletes it on every read, whether or not `round` matched.
- Matching uses the *current* last `## Round N` in `devlog.md` (fence-aware, via `devlog_list_round_starts`), not the marker's own claim — a stale or hand-edited marker must not create a bogus fold.
- If `.span-open` is present and well-formed (valid `ticks_since_checkin` + `max_silent_ticks`), Span Mode wins: the tick is skipped entirely (existing behavior), and `.awaiting-reply` — if also present — is simply deleted with no fold and no new Round.
- A folded tick does not increment `rounds_since_checkpoint` (same treatment as a Span-Mode-skipped tick).
- `.turn-start` is snapshotted **after** whichever path ran (new Round / folded segment / span-skip) — unchanged principle, applies to the new fold path too.
- The folded segment reuses the exact same prompt handling User Input already gets: placeholder `（無 prompt）` when empty, truncate at 4000 chars with the exact truncation notice `（後略，已截斷至 4000 字）`, neutralize inner ` ``` ` to `⟨fence⟩`, then `redact_prompt`.
- Folded segment heading format (exact): `### 段落 <k> - HH:MM（回覆上一輪的問題）` where `<k>` is `1 + ` the count of existing `### 段落` headings already inside that Round's block, and `HH:MM` comes from `date +%H:%M`.
- The segment block is inserted immediately before the target Round's `### Summary` line, fence-aware (must not match a `### Summary` string that appears inside a fenced code block).
- `await-open.sh` behavior: `NOT_ENABLED` (exit 1) if `.enabled` missing; `ALREADY_OPEN` (exit 1) if `.awaiting-reply` already exists; otherwise resolve the current last Round number the same way `span-open.sh` does (`.round-open` first, else last `## Round` in `devlog.md`) and write `{"round": N, "opened_at": "<ISO8601>"}`, print `OPENED=<N>`, exit 0.
- `pause-devlog.sh` deletes `.awaiting-reply` alongside its existing `.span-open` / `.round-open` / `.interrupted` cleanup.
- Fail-open throughout: every new failure path in `round-start.sh` and `await-open.sh` falls back to "no fold" / "no-op", never blocks or crashes the hook.
- Do not modify `enforce-devlog.sh`, `close-open-round.sh`, or `segment-watch.sh` — the spec confirms none of them need to change.
- Follow existing script conventions: `set -uo pipefail`, source shared helpers via `_src="${BASH_SOURCE[0]}"; SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"`, `devlog_lock_acquire`/`trap ... devlog_lock_release` around any read-modify-write of `devlog.md`.

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/await-open.sh` | New. Writes `.devlog/.awaiting-reply` for the current Round (Claude calls this via Bash after closing a Round with a pending question). |
| `hooks/scripts/test-await-open.sh` | New. Self-check for `await-open.sh`. |
| `hooks/scripts/devlog-md.sh` | Modified. Add `devlog_count_segments` and `devlog_insert_before_summary` helpers used by the fold logic. |
| `hooks/scripts/round-start.sh` | Modified. Reads/consumes `.awaiting-reply`; on match, folds the reply into the last Round's segment list instead of opening a new one. |
| `hooks/scripts/test-round-start.sh` | Modified. New scenarios: fold-match, fold-miss (stale round), fold with existing segments (numbering), fold suppressed by valid Span, checkpoint counter not incremented on fold. |
| `hooks/scripts/pause-devlog.sh` | Modified. Also deletes `.awaiting-reply`. |
| `hooks/scripts/test-start-pause-devlog.sh` | Modified. Assert `.awaiting-reply` is deleted by pause. |
| `skills/devlog-tracker/SKILL.md` | Modified. Document Reply Fold: when to open it, what a folded segment looks like, the `AskUserQuestion` distinction. |
| `README.md` | Modified. Add `await-open.sh` to the file tree table. |

Do not create a `reply-fold.sh` standalone script — the fold logic lives inside `round-start.sh` itself (mirrors how the dangling-heal and span-skip logic already live inline there, not as separate scripts).

---

### Task 1: `devlog-md.sh` helpers for segment counting and mid-block insertion

**Files:**
- Modify: `hooks/scripts/devlog-md.sh`
- Create: `hooks/scripts/test-devlog-md.sh`
- Test: `bash hooks/scripts/test-devlog-md.sh`

**Interfaces:**
- Consumes: a `devlog.md`-shaped file path; an existing Round's start line number (from `devlog_list_round_starts`) and end line number (from `devlog_block_end`).
- Produces:
  - `devlog_count_segments FILE START END` → prints an integer: the count of fence-aware `### 段落` headings whose line number is within `[START, END]`.
  - `devlog_insert_before_summary FILE START END TEXT_FILE` → prints the full file content (to stdout) with the contents of `TEXT_FILE` inserted as whole lines immediately before the first fence-aware `### Summary` line found within `[START, END]`. If no `### Summary` line is found in that range, prints the original file unchanged (caller decides what that means — this task itself does not need to handle that case specially, it's a pure text operation).

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-devlog-md.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Self-check for devlog-md.sh's segment-counting and insertion helpers. Run:
#   bash hooks/scripts/test-devlog-md.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected [$expected], got [$actual])"
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

# --- devlog_count_segments: zero segments ----------------------------------
cat > "$TMP_ROOT/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello
```

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
START="$(devlog_list_round_starts "$TMP_ROOT/devlog.md" | awk '$2==1{print $1}')"
END="$(devlog_block_end "$TMP_ROOT/devlog.md" "$START")"
COUNT="$(devlog_count_segments "$TMP_ROOT/devlog.md" "$START" "$END")"
assert_eq "zero segments" "0" "$COUNT"

# --- devlog_count_segments: two existing segments ---------------------------
cat > "$TMP_ROOT/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello
```

### 段落 1 - 09:00
first

### 段落 2 - 09:10
second

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
START="$(devlog_list_round_starts "$TMP_ROOT/devlog.md" | awk '$2==1{print $1}')"
END="$(devlog_block_end "$TMP_ROOT/devlog.md" "$START")"
COUNT="$(devlog_count_segments "$TMP_ROOT/devlog.md" "$START" "$END")"
assert_eq "two existing segments" "2" "$COUNT"

# --- devlog_count_segments: a fenced line that itself looks like a heading
# must not count (fence-awareness, not just the regex anchor) ---------------
cat > "$TMP_ROOT/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
### 段落 1 - 09:00
```

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
START="$(devlog_list_round_starts "$TMP_ROOT/devlog.md" | awk '$2==1{print $1}')"
END="$(devlog_block_end "$TMP_ROOT/devlog.md" "$START")"
COUNT="$(devlog_count_segments "$TMP_ROOT/devlog.md" "$START" "$END")"
assert_eq "fenced mention of 段落 not counted" "0" "$COUNT"

# --- devlog_insert_before_summary: inserts right before ### Summary --------
cat > "$TMP_ROOT/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello
```

### Summary
done

### Handoff
#### 現況
done

### Status
DONE

## Round 2 — 2026-09-09T13:00:00+08:00

### Summary
other round summary marker should not be touched
EOF
printf '### 段落 1 - 09:30（回覆上一輪的問題）\n```text\nmy answer\n```\n\n' > "$TMP_ROOT/segment.txt"
START="$(devlog_list_round_starts "$TMP_ROOT/devlog.md" | awk '$2==1{print $1}')"
END="$(devlog_block_end "$TMP_ROOT/devlog.md" "$START")"
RESULT="$(devlog_insert_before_summary "$TMP_ROOT/devlog.md" "$START" "$END" "$TMP_ROOT/segment.txt")"
assert_contains "inserted segment text present" "my answer" "$RESULT"
# The inserted block must appear before Round 1's Summary, not Round 2's.
BEFORE_R1_SUMMARY="$(printf '%s\n' "$RESULT" | awk '/my answer/{print NR} /^### Summary$/{print NR; exit}')"
FIRST_LINE="$(printf '%s\n' "$BEFORE_R1_SUMMARY" | head -1)"
SECOND_LINE="$(printf '%s\n' "$BEFORE_R1_SUMMARY" | tail -1)"
if [ "$FIRST_LINE" -lt "$SECOND_LINE" ]; then
  echo "PASS: segment text appears before Round 1's ### Summary"
else
  echo "FAIL: segment text did not land before Round 1's ### Summary"
  FAIL=1
fi
ROUND2_COUNT="$(printf '%s\n' "$RESULT" | grep -c 'other round summary marker')"
assert_eq "round 2 summary untouched (still exactly once)" "1" "$ROUND2_COUNT"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/test-devlog-md.sh`

Expected: FAIL with `devlog_count_segments: command not found` (or similar) — the functions don't exist yet.

- [ ] **Step 3: Add the two helpers to `devlog-md.sh`**

Append to `hooks/scripts/devlog-md.sh` (after the existing `devlog_round_status` function):

```bash

devlog_count_segments() {
  awk -v start="$2" -v end="$3" '
    NR < start || NR > end { next }
    /^```/ { fence = !fence; next }
    !fence && /^### 段落 / { count++ }
    END { print count + 0 }
  ' "$1"
}

devlog_insert_before_summary() {
  local file="$1" start="$2" end="$3" text_file="$4"
  awk -v start="$start" -v end="$end" -v textfile="$text_file" '
    BEGIN {
      inserted = 0
      while ((getline line < textfile) > 0) {
        ins[ni++] = line
      }
      close(textfile)
    }
    {
      if (!inserted && NR >= start && NR <= end && !fence && $0 ~ /^### Summary$/) {
        for (i = 0; i < ni; i++) print ins[i]
        inserted = 1
      }
      if ($0 ~ /^```/) fence = !fence
      print
    }
  ' "$file"
}
```

- [ ] **Step 4: Run the self-check**

Run: `bash hooks/scripts/test-devlog-md.sh`

Expected: `All checks passed.` and exit 0.

- [ ] **Step 5: Run the full existing suite to confirm no regressions**

Run: `bash hooks/scripts/run-tests.sh`

Expected: `All hook self-checks passed.` (adding functions to a sourced file must not break any existing script that sources it).

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/devlog-md.sh hooks/scripts/test-devlog-md.sh
git commit -m "$(cat <<'EOF'
Add devlog-md.sh helpers for counting and inserting segment blocks

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `await-open.sh` — write the one-shot reply marker

**Files:**
- Create: `hooks/scripts/await-open.sh`
- Create: `hooks/scripts/test-await-open.sh`
- Test: `bash hooks/scripts/test-await-open.sh`

**Interfaces:**
- Consumes: `CLAUDE_PROJECT_DIR`; `.devlog/.enabled`; `.devlog/.awaiting-reply` (existence check); `.devlog/.round-open` (`round` field via `json_int_get`); `.devlog/devlog.md` (via `devlog_list_round_starts`, sourced from `devlog-md.sh`).
- Produces: on stdout, `NOT_ENABLED` (exit 1), `ALREADY_OPEN` (exit 1), or `OPENED=<N>` (exit 0) after writing `.devlog/.awaiting-reply` as `{"round": <N>, "opened_at": "<ISO8601>"}`.

- [ ] **Step 1: Write the failing self-check**

Create `hooks/scripts/test-await-open.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Self-check for await-open.sh. Run:
#   bash hooks/scripts/test-await-open.sh
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

# --- 1: not enabled -> NOT_ENABLED, no file --------------------------------
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_exit "not enabled -> exit 1" 1 $?
assert_contains "reports NOT_ENABLED" "NOT_ENABLED" "$OUT"
if [ -f "$DEVLOG_DIR/.awaiting-reply" ]; then
  echo "FAIL: .awaiting-reply should not exist when disabled"
  FAIL=1
else
  echo "PASS: no .awaiting-reply when disabled"
fi

touch "$DEVLOG_DIR/.enabled"

# --- 2: resolves round from .round-open when present -----------------------
printf '%s\n' '{"round": 4, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_exit "opens -> exit 0" 0 $?
assert_contains "reports OPENED=4" "OPENED=4" "$OUT"
ROUND_FIELD="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.awaiting-reply" | grep -o '[0-9]\+$')"
if [ "$ROUND_FIELD" = "4" ]; then
  echo "PASS: .awaiting-reply round=4 (from .round-open)"
else
  echo "FAIL: expected round=4, got $ROUND_FIELD"
  FAIL=1
fi
grep -q '"opened_at"' "$DEVLOG_DIR/.awaiting-reply" \
  && echo "PASS: opened_at field present" || { echo "FAIL: opened_at missing"; FAIL=1; }
rm -f "$DEVLOG_DIR/.awaiting-reply" "$DEVLOG_DIR/.round-open"

# --- 3: falls back to last ## Round in devlog.md when .round-open absent ---
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### Summary
done

### Handoff
#### 現況
done

### Status
DONE

## Round 2 — 2026-09-09T13:00:00+08:00

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_contains "falls back to last Round in devlog.md" "OPENED=2" "$OUT"
rm -f "$DEVLOG_DIR/.awaiting-reply"

# --- 4: already open -> ALREADY_OPEN, does not overwrite --------------------
printf '%s\n' '{"round": 99, "opened_at": "sentinel"}' > "$DEVLOG_DIR/.awaiting-reply"
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_exit "already open -> exit 1" 1 $?
assert_contains "reports ALREADY_OPEN" "ALREADY_OPEN" "$OUT"
grep -q 'sentinel' "$DEVLOG_DIR/.awaiting-reply" \
  && echo "PASS: existing marker left untouched" || { echo "FAIL: existing marker was overwritten"; FAIL=1; }
rm -f "$DEVLOG_DIR/.awaiting-reply" "$DEVLOG_DIR/devlog.md"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/test-await-open.sh`

Expected: FAIL because `await-open.sh` does not exist.

- [ ] **Step 3: Write `await-open.sh`**

Create `hooks/scripts/await-open.sh` with this exact content:

```bash
#!/usr/bin/env bash
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"
# shellcheck source=devlog-md.sh
. "$SCRIPT_DIR/devlog-md.sh"

DEVLOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.devlog"
[ -f "$DEVLOG_DIR/.enabled" ] || { echo "NOT_ENABLED" >&2; exit 1; }
[ ! -e "$DEVLOG_DIR/.awaiting-reply" ] || { echo "ALREADY_OPEN" >&2; exit 1; }
ROUND=""
[ ! -f "$DEVLOG_DIR/.round-open" ] || ROUND="$(json_int_get "$DEVLOG_DIR/.round-open" round)"
if [ -z "$ROUND" ] && [ -f "$DEVLOG_DIR/devlog.md" ]; then
  ROUND="$(devlog_list_round_starts "$DEVLOG_DIR/devlog.md" | awk 'END { print $2 }')"
fi
[ -n "$ROUND" ] || { echo "NO_ROUND" >&2; exit 1; }
OPENED_AT="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
printf '{"round": %s, "opened_at": "%s"}\n' "$ROUND" "$OPENED_AT" > "$DEVLOG_DIR/.awaiting-reply" || exit 1
printf 'OPENED=%s\n' "$ROUND"
```

Then make it executable:

```bash
chmod +x hooks/scripts/await-open.sh
```

- [ ] **Step 4: Run the self-check**

Run: `bash hooks/scripts/test-await-open.sh`

Expected: `All checks passed.` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/await-open.sh hooks/scripts/test-await-open.sh
git commit -m "$(cat <<'EOF'
Add await-open.sh to mark a Round as awaiting the user's next reply

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Fold logic in `round-start.sh`

**Files:**
- Modify: `hooks/scripts/round-start.sh`
- Modify: `hooks/scripts/test-round-start.sh`
- Test: `bash hooks/scripts/test-round-start.sh`

**Interfaces:**
- Consumes: `devlog_list_round_starts`, `devlog_block_end`, `devlog_count_segments`, `devlog_insert_before_summary` (from Task 1's `devlog-md.sh`); `json_int_get` (existing, from `json-field.sh`); `redact_prompt` (existing, from `redact-prompt.sh`).
- Produces: unless a fold happens, existing new-Round behavior is unchanged. On a fold match: no new `## Round`; a `### 段落 <k> - HH:MM（回覆上一輪的問題）` block (fenced prompt body) inserted before that Round's `### Summary`; `.round-open` rewritten to `{"round": <matched N>, "opened_at": "<ISO8601>"}`; `rounds_since_checkpoint` not incremented for this tick; `.turn-start` snapshotted after the insert.

- [ ] **Step 1: Add failing self-check scenarios to `test-round-start.sh`**

Immediately before the final `if [ "$FAIL" -eq 0 ]; then` block, insert:

```bash
# --- 11: .awaiting-reply matches last Round -> folds as a segment ----------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.checkpoint-state"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 5 — 2026-09-09T12:00:00+08:00

### User Input
```text
what color should the button be?
```

### Summary
Asked the user to pick a color.

### Handoff
#### 現況
Waiting on the user's color choice.
#### 下一步
Apply the chosen color once they answer.

### Status
BLOCKED
EOF
printf '%s\n' '{"round": 5, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"blue please"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
UNFENCED_ROUNDS="$(awk '/^[ \t]*```/{f=!f} !f && /^## Round /{c++} END{print c+0}' "$DEVLOG_DIR/devlog.md")"
if [ "$UNFENCED_ROUNDS" = "1" ]; then
  echo "PASS: fold did not open a second Round"
else
  echo "FAIL: expected 1 unfenced Round heading, got $UNFENCED_ROUNDS"
  FAIL=1
fi
assert_contains "folded segment heading" "### 段落 1 -" "$BODY"
assert_contains "folded segment marks it a reply" "（回覆上一輪的問題）" "$BODY"
assert_contains "folded segment keeps user's words" "blue please" "$BODY"
# segment must land before Summary, not after
SEG_LINE="$(grep -n '### 段落 1' "$DEVLOG_DIR/devlog.md" | head -1 | cut -d: -f1)"
SUM_LINE="$(grep -n '^### Summary$' "$DEVLOG_DIR/devlog.md" | head -1 | cut -d: -f1)"
if [ "$SEG_LINE" -lt "$SUM_LINE" ]; then
  echo "PASS: folded segment inserted before Summary"
else
  echo "FAIL: folded segment landed after Summary (seg=$SEG_LINE summary=$SUM_LINE)"
  FAIL=1
fi
if [ -f "$DEVLOG_DIR/.awaiting-reply" ]; then
  echo "FAIL: .awaiting-reply should be consumed after use"
  FAIL=1
else
  echo "PASS: .awaiting-reply consumed"
fi
OPEN_N="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.round-open" | grep -o '[0-9]\+$')"
if [ "$OPEN_N" = "5" ]; then
  echo "PASS: .round-open rewritten to the folded Round (5)"
else
  echo "FAIL: expected .round-open round=5, got $OPEN_N"
  FAIL=1
fi
AFTER_HASH="$(cksum < "$DEVLOG_DIR/devlog.md")"
START_HASH="$(cat "$DEVLOG_DIR/.turn-start")"
if [ "$AFTER_HASH" = "$START_HASH" ]; then
  echo "PASS: .turn-start matches post-fold hash"
else
  echo "FAIL: .turn-start should be captured after the fold insert"
  FAIL=1
fi

# --- 12: second reply on the same Round numbers segments incrementally -----
printf '%s\n' '{"round": 5, "opened_at": "2026-09-09T12:05:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"actually make it green"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "first segment still present" "### 段落 1 -" "$BODY"
assert_contains "second segment numbered 2" "### 段落 2 -" "$BODY"
assert_contains "second segment content" "actually make it green" "$BODY"

# --- 13: .awaiting-reply round is stale -> dropped, normal new Round opens -
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
printf '%s\n' '{"round": 99, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"unrelated new request"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "stale marker -> normal new Round 2 opened" "## Round 2 —" "$BODY"
assert_not_contains "stale marker -> no segment inserted" "### 段落" "$BODY"
if [ -f "$DEVLOG_DIR/.awaiting-reply" ]; then
  echo "FAIL: stale .awaiting-reply should still be consumed"
  FAIL=1
else
  echo "PASS: stale .awaiting-reply consumed without folding"
fi

# --- 14: valid Span Mode suppresses the fold and just consumes the marker --
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 9 — 2026-09-09T12:00:00+08:00

### Summary
in progress

### Handoff
#### 現況
running
#### 下一步
keep going

### Status
IN_PROGRESS
EOF
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 9,
  "opened_at": "2026-09-09T00:00:00+08:00",
  "ticks_since_checkin": 0,
  "max_silent_ticks": 5
}
SPANEOF
printf '%s\n' '{"round": 9, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"automated tick"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_not_contains "span suppresses fold: no segment" "### 段落" "$BODY"
UNFENCED_ROUNDS="$(awk '/^[ \t]*```/{f=!f} !f && /^## Round /{c++} END{print c+0}' "$DEVLOG_DIR/devlog.md")"
if [ "$UNFENCED_ROUNDS" = "1" ]; then
  echo "PASS: span suppresses fold: no new Round either"
else
  echo "FAIL: expected 1 unfenced Round heading, got $UNFENCED_ROUNDS"
  FAIL=1
fi
if [ -f "$DEVLOG_DIR/.awaiting-reply" ]; then
  echo "FAIL: .awaiting-reply should be consumed even when span suppresses the fold"
  FAIL=1
else
  echo "PASS: .awaiting-reply consumed under an active span"
fi
rm -f "$DEVLOG_DIR/.span-open"

# --- 15: fold does not increment rounds_since_checkpoint --------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### Summary
waiting

### Handoff
#### 現況
waiting on reply
#### 下一步
apply the answer

### Status
BLOCKED
EOF
printf '%s\n' '{"rounds_since_checkpoint": 3, "max_silent_rounds": 20, "checkpoint_marker_count": 0}' > "$DEVLOG_DIR/.checkpoint-state"
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"the reply"}' | bash "$SCRIPT_DIR/round-start.sh"
CP="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP" = "3" ]; then
  echo "PASS: fold does not increment rounds_since_checkpoint"
else
  echo "FAIL: expected rounds_since_checkpoint to stay 3, got $CP"
  FAIL=1
fi
rm -f "$DEVLOG_DIR/.checkpoint-state"
```

- [ ] **Step 2: Run it to verify the new cases fail**

Run: `bash hooks/scripts/test-round-start.sh`

Expected: FAIL on scenario 11 onward (`round-start.sh` doesn't know about `.awaiting-reply` yet — it will open a second `## Round` instead of folding).

- [ ] **Step 3: Implement the fold in `round-start.sh`**

First, add the `devlog-md.sh` source line. In `hooks/scripts/round-start.sh`, change:

```bash
# shellcheck source=devlog-lock.sh
. "$HOOKS_DIR/devlog-lock.sh"
```

to:

```bash
# shellcheck source=devlog-lock.sh
. "$HOOKS_DIR/devlog-lock.sh"
# shellcheck source=devlog-md.sh
. "$HOOKS_DIR/devlog-md.sh"
```

Next, add the `AWAITING_FILE` path alongside the other path variables. Change:

```bash
ROUND_OPEN="$DEVLOG_DIR/.round-open"
```

to:

```bash
ROUND_OPEN="$DEVLOG_DIR/.round-open"
AWAITING_FILE="$DEVLOG_DIR/.awaiting-reply"
```

Next, insert the fold-detection block right after the existing dangling-heal block and before the `SPAN_SKIP=0` block. Change:

```bash
if [ -f "$ROUND_OPEN" ]; then
  bash "$HOOKS_DIR/close-open-round.sh" "dangling:next_prompt" || true
fi

SPAN_SKIP=0
```

to:

```bash
if [ -f "$ROUND_OPEN" ]; then
  bash "$HOOKS_DIR/close-open-round.sh" "dangling:next_prompt" || true
fi

FOLD_ROUND=""
if [ -f "$AWAITING_FILE" ]; then
  AWAIT_ROUND="$(json_int_get "$AWAITING_FILE" round)"
  rm -f "$AWAITING_FILE" 2>/dev/null || true
  case "$AWAIT_ROUND" in
    ''|*[!0-9]*) AWAIT_ROUND='' ;;
  esac
  if [ -n "$AWAIT_ROUND" ] && [ -f "$DEVLOG_FILE" ]; then
    CURRENT_LAST="$(devlog_list_round_starts "$DEVLOG_FILE" | awk 'END { print $2 }')"
    if [ "$CURRENT_LAST" = "$AWAIT_ROUND" ]; then
      FOLD_ROUND="$AWAIT_ROUND"
    fi
  fi
fi

SPAN_SKIP=0
```

Next, make Span Mode take precedence over a fold when both are present. Inside the existing `SPAN_SKIP` block, no change is needed — but the fold must be suppressed when `SPAN_SKIP` ends up `1`. Change the guard on the whole prompt-writing block from:

```bash
if [ "$SPAN_SKIP" -eq 0 ]; then
```

to:

```bash
if [ "$SPAN_SKIP" -eq 1 ]; then
  FOLD_ROUND=""
fi

if [ -n "$FOLD_ROUND" ]; then
  if [ -z "$PROMPT" ]; then
    PROMPT="（無 prompt）"
  fi
  TRUNC_NOTE=""
  if [ "${#PROMPT}" -gt 4000 ]; then
    PROMPT="${PROMPT:0:4000}"
    TRUNC_NOTE="（後略，已截斷至 4000 字）"
  fi
  PROMPT="$(printf '%s' "$PROMPT" | sed 's/```/⟨fence⟩/g')"
  PROMPT="$(printf '%s' "$PROMPT" | redact_prompt)"

  TS="$(date +%H:%M 2>/dev/null || echo unknown)"
  FULL_TS="$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo unknown)"
  START_LINE="$(devlog_list_round_starts "$DEVLOG_FILE" | awk -v r="$FOLD_ROUND" '$2==r{print $1}')"
  END_LINE="$(devlog_block_end "$DEVLOG_FILE" "$START_LINE")"
  SEG_N=$(( $(devlog_count_segments "$DEVLOG_FILE" "$START_LINE" "$END_LINE") + 1 ))

  SEG_TMP="$DEVLOG_DIR/.segment-insert.tmp"
  {
    printf '### 段落 %s - %s（回覆上一輪的問題）\n' "$SEG_N" "$TS"
    printf '```text\n'
    printf '%s\n' "$PROMPT"
    printf '```\n'
    if [ -n "$TRUNC_NOTE" ]; then
      printf '%s\n' "$TRUNC_NOTE"
    fi
    printf '\n'
  } > "$SEG_TMP" 2>/dev/null || true

  if [ -f "$SEG_TMP" ]; then
    devlog_insert_before_summary "$DEVLOG_FILE" "$START_LINE" "$END_LINE" "$SEG_TMP" > "$DEVLOG_FILE.tmp" 2>/dev/null \
      && mv "$DEVLOG_FILE.tmp" "$DEVLOG_FILE" 2>/dev/null || true
    rm -f "$SEG_TMP" 2>/dev/null || true
  fi

  printf '{"round": %s, "opened_at": "%s"}\n' "$FOLD_ROUND" "$FULL_TS" > "$ROUND_OPEN" 2>/dev/null || true
elif [ "$SPAN_SKIP" -eq 0 ]; then
```

Leave the rest of that block (the original body from `if [ -z "$PROMPT" ]; then ... fi` through the closing `fi` of the original `if [ "$SPAN_SKIP" -eq 0 ]; then` block) exactly as-is — only the opening condition line changes from `if [ "$SPAN_SKIP" -eq 0 ]; then` to the `elif [ "$SPAN_SKIP" -eq 0 ]; then` shown above, now preceded by the new `if [ -n "$FOLD_ROUND" ]; then ... elif` chain, and its final closing `fi` now also closes this new `if/elif` chain (no extra `fi` needed since it's the same block, just with a new leading branch).

Finally, a folded tick must not count as a new Round for Checkpoint Mode purposes (Global Constraints). The existing checkpoint-increment guard only checks Span Mode; it needs to also skip when a fold happened. Change:

```bash
if [ "$SPAN_WILL_PASS_THROUGH" -eq 0 ] && [ -f "$CHECKPOINT_FILE" ]; then
```

to:

```bash
if [ "$SPAN_WILL_PASS_THROUGH" -eq 0 ] && [ -z "$FOLD_ROUND" ] && [ -f "$CHECKPOINT_FILE" ]; then
```

(`FOLD_ROUND` is non-empty only when a fold actually happened — it's reset to `""` above whenever Span Mode suppressed it, so this correctly still increments on an ordinary new Round or a Span-Mode-skipped tick, and only skips on a genuine fold.)

- [ ] **Step 4: Run the self-check**

Run: `bash hooks/scripts/test-round-start.sh`

Expected: `All checks passed.` and exit 0.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bash hooks/scripts/run-tests.sh`

Expected: `All hook self-checks passed.`

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/round-start.sh hooks/scripts/test-round-start.sh
git commit -m "$(cat <<'EOF'
Fold a reply into the awaited Round instead of opening a new one

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `pause-devlog.sh` cleanup

**Files:**
- Modify: `hooks/scripts/pause-devlog.sh`
- Modify: `hooks/scripts/test-start-pause-devlog.sh`
- Test: `bash hooks/scripts/test-start-pause-devlog.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `/devlog-tracker:pause` also deletes `.devlog/.awaiting-reply`.

- [ ] **Step 1: Add the failing assertion**

In `hooks/scripts/test-start-pause-devlog.sh`, change:

```bash
# pause
touch "$TMP_ROOT/.devlog/.span-open" "$TMP_ROOT/.devlog/.round-open" "$TMP_ROOT/.devlog/.interrupted"
echo 'keep me' > "$TMP_ROOT/.devlog/devlog.md"
OUT="$(bash "$SCRIPT_DIR/pause-devlog.sh")"
assert_exit "pause -> 0" 0 $?
assert_not_file "enabled gone" "$TMP_ROOT/.devlog/.enabled"
assert_not_file "span gone" "$TMP_ROOT/.devlog/.span-open"
assert_not_file "round-open gone" "$TMP_ROOT/.devlog/.round-open"
assert_not_file "interrupted gone" "$TMP_ROOT/.devlog/.interrupted"
assert_file "log kept" "$TMP_ROOT/.devlog/devlog.md"
assert_file "checkpoint kept" "$TMP_ROOT/.devlog/.checkpoint-state"
```

to:

```bash
# pause
touch "$TMP_ROOT/.devlog/.span-open" "$TMP_ROOT/.devlog/.round-open" "$TMP_ROOT/.devlog/.interrupted" "$TMP_ROOT/.devlog/.awaiting-reply"
echo 'keep me' > "$TMP_ROOT/.devlog/devlog.md"
OUT="$(bash "$SCRIPT_DIR/pause-devlog.sh")"
assert_exit "pause -> 0" 0 $?
assert_not_file "enabled gone" "$TMP_ROOT/.devlog/.enabled"
assert_not_file "span gone" "$TMP_ROOT/.devlog/.span-open"
assert_not_file "round-open gone" "$TMP_ROOT/.devlog/.round-open"
assert_not_file "interrupted gone" "$TMP_ROOT/.devlog/.interrupted"
assert_not_file "awaiting-reply gone" "$TMP_ROOT/.devlog/.awaiting-reply"
assert_file "log kept" "$TMP_ROOT/.devlog/devlog.md"
assert_file "checkpoint kept" "$TMP_ROOT/.devlog/.checkpoint-state"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/test-start-pause-devlog.sh`

Expected: FAIL on `awaiting-reply gone` (the file still exists after pause).

- [ ] **Step 3: Update `pause-devlog.sh`**

Change:

```bash
rm -f "$DEVLOG_DIR/.enabled" "$DEVLOG_DIR/.span-open" \
  "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.interrupted"
```

to:

```bash
rm -f "$DEVLOG_DIR/.enabled" "$DEVLOG_DIR/.span-open" \
  "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.interrupted" \
  "$DEVLOG_DIR/.awaiting-reply"
```

- [ ] **Step 4: Run the self-check**

Run: `bash hooks/scripts/test-start-pause-devlog.sh`

Expected: `All checks passed.` and exit 0.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bash hooks/scripts/run-tests.sh`

Expected: `All hook self-checks passed.`

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/pause-devlog.sh hooks/scripts/test-start-pause-devlog.sh
git commit -m "$(cat <<'EOF'
Delete .awaiting-reply on /devlog-tracker:pause

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Document Reply Fold in `SKILL.md` and `README.md`

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: authoring instructions Claude follows when deciding whether to open `.awaiting-reply`, and what a folded segment looks like when reading `devlog.md` back.

- [ ] **Step 1: Add a "Reply Fold" section to `SKILL.md`**

In `skills/devlog-tracker/SKILL.md`, insert a new section immediately after the existing `## Round Segments：單輪內的階段性記錄` section (right before `## Span Mode：橫跨多次自動續接的長任務`), with this exact content:

````markdown
## Reply Fold：把「Claude 提問、user 回答」記成同一個 Round

一輪如果是 Claude 用純文字結尾提出一個具體問題（不是用 `AskUserQuestion`
工具、而是整個 turn 就在這句問題上結束），下一則使用者訊息通常就是答案，
不是新話題。預設行為（每個 `UserPromptSubmit` 開一個新 `## Round`）會把這
組問答拆成兩個不相關的 Round。Reply Fold 讓這種情況折進同一個 Round，記
成一個 `### 段落`。

**跟 `AskUserQuestion` 工具的差異：** 用 `AskUserQuestion` 問問題時，問題
跟答案都在同一個 turn 裡（呼叫工具、拿到結果，沒有中間的 Stop），根本不
會產生第二個 Round，不需要也不該用 Reply Fold。Reply Fold 只處理「整個
turn 已經結束、下一則訊息才拿到答案」這種情況。

**什麼時候該開：** 這一輪的 Summary／Handoff／Status 寫完、確定要用文字
問題結束這個 turn（Status 常見是 `BLOCKED`，但 `IN_PROGRESS` 也可能）時，
在結束 turn 之前用 Bash 執行：

```bash
bash hooks/scripts/await-open.sh
```

這會寫入 `.devlog/.awaiting-reply`，記住「下一則訊息大概是在回答這個
Round」。不需要使用者下任何指令，也不用手寫這個 JSON。

**下一則訊息進來之後會自動發生什麼事：** `round-start.sh` 看到
`.awaiting-reply` 且輪次跟目前最後一個 `## Round` 吻合，就不開新 Round，
改成在那個 Round 的 `### Summary` 之前插入一個新段落：

```markdown
### 段落 2 - 14:32（回覆上一輪的問題）
```text
<使用者這則訊息的原話，跟 User Input 一樣的截斷/遮罩規則>
```
```

`.devlog/.round-open` 會重新指向這個 Round，讓這輪如果又意外中斷，
`INTERRUPTED` 一樣能正確蓋在同一個 Round 上。折入之後 Claude 照常編輯
這個 Round 的 Summary／Handoff／Status，反映答案後的結果。

**猜錯的處理：** hook 沒辦法驗證「下一則訊息真的是在回答」，只看
`.awaiting-reply` 有沒有開著。如果開了之後使用者其實問了不相干的新問題，
還是會被自動折進舊 Round 當一個段落。發現猜錯時，在那個段落裡說明「其實
是新話題」，然後自己手動開一個新的 `## Round` 接手新請求——不用回頭改寫
被誤折的段落。

**跟 Span Mode 的關係：** 兩者同時存在時（不常見），Span Mode 優先——這個
tick 會被 Span Mode 安靜跳過，`.awaiting-reply` 照樣被消耗掉但不產生任何
折入。

**跟 checkpoint 計數的關係：** 折入的這個 tick 不算開新 Round，
`rounds_since_checkpoint` 不會遞增，跟 Span Mode 跳過的 tick 待遇一致。
````

- [ ] **Step 2: Add `await-open.sh` to the README file tree**

In `README.md`, change:

```
│       ├── span-open.sh / span-close.sh # /span：寫或刪 .span-open
```

to:

```
│       ├── span-open.sh / span-close.sh # /span：寫或刪 .span-open
│       ├── await-open.sh                # Reply Fold：寫 .awaiting-reply
```

- [ ] **Step 3: Verify the doc changes render sanely**

Run: `grep -n "Reply Fold" skills/devlog-tracker/SKILL.md README.md hooks/scripts/*.sh docs/design/reply-fold.md`

Expected: at least one match in `SKILL.md`, and the design doc — confirms the section landed and nothing broke the file.

- [ ] **Step 4: Commit**

```bash
git add skills/devlog-tracker/SKILL.md README.md
git commit -m "$(cat <<'EOF'
Document Reply Fold in SKILL.md and the README file tree

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Final Verification

- [ ] Run `bash hooks/scripts/run-tests.sh` once more from a clean checkout state and confirm `All hook self-checks passed.`
- [ ] Manually re-read `docs/design/reply-fold.md` against the implemented behavior — confirm every mechanism described there (marker file shape, fold insertion point, Span Mode precedence, checkpoint non-increment, pause cleanup) has a corresponding passing test from Tasks 1-4.
