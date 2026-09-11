#!/usr/bin/env bash
# Self-check for session-start-devlog.sh, including the Span Mode
# resume-context note. No framework — plain assert-and-exit, matching this
# repo's existing style. Run directly:
#   bash hooks/scripts/test-session-start-devlog.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=1
  fi
}

write_round() {
  local n="$1" status="$2"
  cat >> "$DEVLOG_DIR/devlog.md" <<EOF
## Round ${n} — 2026-09-09T12:00:00+08:00

### User Input
\`\`\`text
prompt ${n} with lots of bulk
\`\`\`

### 段落 1 - 12:01
secret intermediate ${n}

### Summary
summary ${n}

### Handoff
#### 現況
handoff ${n}

### Status
${status}
EOF
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

# --- Scenario 5: startup heals open round then still injects --------------
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
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
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

# --- Scenario 6: compact must NOT heal; Stop still enforces ---------------
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
mid compact
```

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/devlog.md" > "$DEVLOG_DIR/.turn-start"
OUTPUT="$(echo '{"source":"compact"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "compact still injects Round 1" "Round 1" "$OUTPUT"
FILE="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "compact leaves Status IN_PROGRESS" "IN_PROGRESS" "$FILE"
assert_not_contains "compact must not stamp INTERRUPTED" "INTERRUPTED" "$FILE"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "PASS: compact left .round-open in place"
else
  echo "FAIL: compact SessionStart must not delete .round-open"
  FAIL=1
fi
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "after compact skip-heal, Stop still enforces (hash equal) -> exit 2" 2 $?

# --- Scenario 7: hooks.json SessionStart matcher includes fork -------------
HOOKS_JSON="$SCRIPT_DIR/../hooks.json"
if grep -q '"matcher": "startup|resume|clear|compact|fork"' "$HOOKS_JSON"; then
  echo "PASS: SessionStart matcher includes fork"
else
  echo "FAIL: SessionStart matcher must be exactly startup|resume|clear|compact|fork"
  FAIL=1
fi

# --- Scenario 8: source=fork heals an open skeleton (script already does) --
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
fork me
```

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
OUTPUT="$(echo '{"source":"fork"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "fork still shows Round 1" "Round 1" "$OUTPUT"
assert_contains "fork heal reason" "dangling:session_start" "$OUTPUT"
FILE="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "fork stamped INTERRUPTED" "INTERRUPTED" "$FILE"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: fork SessionStart should delete .round-open after heal"
  FAIL=1
else
  echo "PASS: fork SessionStart deleted .round-open"
fi

# --- Scenario 9: source=clear does not inject; still heals open round ------
rm -f "$DEVLOG_DIR/.span-open"
touch "$DEVLOG_DIR/.enabled"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
cleared
```

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
OUTPUT="$(echo '{"source":"clear"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
if [ -z "$OUTPUT" ]; then
  echo "PASS: source=clear with open round -> silent stdout"
else
  echo "FAIL: source=clear must not inject context, got: $OUTPUT"
  FAIL=1
fi
FILE="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "clear still stamps INTERRUPTED on disk" "INTERRUPTED" "$FILE"
assert_contains "clear heal reason is on disk not stdout" "dangling:session_start" "$FILE"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: clear SessionStart should delete .round-open after heal"
  FAIL=1
else
  echo "PASS: clear SessionStart deleted .round-open"
fi

# --- Scenario 10: source=clear with closed log and open span -> silent -----
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
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{
  "round": 1,
  "opened_at": "2026-09-08T21:40:00+08:00",
  "ticks_since_checkin": 2,
  "max_silent_ticks": 5
}
SPANEOF
OUTPUT="$(echo '{"source":"clear"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
if [ -z "$OUTPUT" ]; then
  echo "PASS: source=clear with span -> silent stdout"
else
  echo "FAIL: source=clear must not inject span warning or rounds, got: $OUTPUT"
  FAIL=1
fi
assert_not_contains "clear must not mention 開啟中的 span" "開啟中的 span" "$OUTPUT"
rm -f "$DEVLOG_DIR/.span-open"

# --- Scenario 11: source=resume still injects after the clear exception ----
OUTPUT="$(echo '{"source":"resume"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "resume still injects Round 1" "Round 1" "$OUTPUT"

# --- Scenario 12: startup does not interrupt a completed last Round ---------
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
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "startup still injects Round 1" "Round 1" "$OUTPUT"
FILE="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "startup recovered keeps DONE" $'### Status\nDONE' "$FILE"
assert_not_contains "startup must not stamp a completed Round" "INTERRUPTED" "$FILE"
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: startup recovered-complete should delete .round-open"
  FAIL=1
else
  echo "PASS: startup recovered-complete deleted .round-open"
fi

# --- Scenario 13: excerpt is last two rounds, not eight -------------------
: > "$DEVLOG_DIR/devlog.md"
rm -f "$DEVLOG_DIR/.span-open"
n=1
while [ "$n" -le 8 ]; do
  write_round "$n" DONE
  n=$((n + 1))
done
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "excerpt names Round 8" "Round 8" "$OUTPUT"
assert_contains "excerpt names Round 7" "Round 7" "$OUTPUT"
assert_not_contains "excerpt drops Round 6" "Round 6" "$OUTPUT"
assert_not_contains "excerpt drops 段落" "secret intermediate" "$OUTPUT"
assert_not_contains "excerpt drops User Input when Summary exists" "prompt 8 with lots of bulk" "$OUTPUT"
assert_contains "excerpt keeps Summary" "summary 8" "$OUTPUT"
assert_contains "excerpt keeps Handoff" "handoff 8" "$OUTPUT"

# --- Scenario 14: last Checkpoint is included even if older than last 2 ---
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'

## Checkpoint（Round 1-6 摘要）
old checkpoint body
EOF
write_round 9 DONE
write_round 10 DONE
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "includes last checkpoint" "old checkpoint body" "$OUTPUT"
assert_contains "still has Round 10" "Round 10" "$OUTPUT"
assert_not_contains "still drops Round 8 body after more writes" "summary 8" "$OUTPUT"

# --- Scenario 15: fenced ## Round inside User Input is not a real Round ---
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
## Round 99 — fake
```

### Summary
real one

### Handoff
#### 現況
real handoff

### Status
DONE
EOF
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "fence-aware uses Round 1" "Round 1" "$OUTPUT"
assert_not_contains "fence-aware ignores Round 99 heading as a round" "Round 99" "$OUTPUT"

# --- Scenario 16: skeleton last Round includes User Input -----------------
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'

## Round 2 — 2026-09-09T12:01:00+08:00

### User Input
```text
unfinished prompt
```

### Status
IN_PROGRESS
EOF
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "skeleton User Input is shown" "unfinished prompt" "$OUTPUT"

# --- Scenario 17: clear still silent with a long log ----------------------
OUTPUT="$(echo '{"source":"clear"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
if [ -z "$OUTPUT" ]; then echo "PASS: clear still silent after excerpt change"
else echo "FAIL: clear injected: $OUTPUT"; FAIL=1; fi

# --- Scenario: Kept 索引 block is surfaced in the injected excerpt ---------
: > "$DEVLOG_DIR/devlog.md"
write_round 1 DONE
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'

## Kept 索引
- `devlog.topic-a.md`：Round 1-1，kept_at 2026-09-10T00:00:00+08:00
EOF
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "startup excerpt includes Kept 索引 heading" "## Kept 索引" "$OUTPUT"
assert_contains "startup excerpt includes the kept-file line" "devlog.topic-a.md" "$OUTPUT"

# --- Scenario: no Kept 索引 block -> excerpt omits the heading entirely ----
: > "$DEVLOG_DIR/devlog.md"
write_round 1 DONE
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_not_contains "no Kept 索引 block -> excerpt has no such heading" "## Kept 索引" "$OUTPUT"

# --- Scenario: source=clear still prints nothing, even with a Kept 索引 ----
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'

## Kept 索引
- `devlog.topic-a.md`：Round 1-1，kept_at 2026-09-10T00:00:00+08:00
EOF
OUTPUT="$(echo '{"source":"clear"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
if [ -z "$OUTPUT" ]; then
  echo "PASS: source=clear stays silent even with a Kept 索引 block present"
else
  echo "FAIL: source=clear must not inject anything, got: $OUTPUT"
  FAIL=1
fi

# --- Scenario: Lessons 索引 block is surfaced in the injected excerpt ------
# (docs/design/lessons-mode.md「## Lessons 索引」)
: > "$DEVLOG_DIR/devlog.md"
write_round 1 DONE
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'

## Lessons 索引
- `devlog.lessons.span-mode-detour.md`：1 則，最新一則「先卡住了。」（updated_at 2026-09-12T00:00:00+08:00）
EOF
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_contains "startup excerpt includes Lessons 索引 heading" "## Lessons 索引" "$OUTPUT"
assert_contains "startup excerpt includes the lessons-file line" "devlog.lessons.span-mode-detour.md" "$OUTPUT"

# --- Scenario: no Lessons 索引 block -> excerpt omits the heading entirely -
: > "$DEVLOG_DIR/devlog.md"
write_round 1 DONE
OUTPUT="$(echo '{"source":"startup"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
assert_not_contains "no Lessons 索引 block -> excerpt has no such heading" "## Lessons 索引" "$OUTPUT"

# --- Scenario: source=clear still prints nothing, even with a Lessons 索引 -
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'

## Lessons 索引
- `devlog.lessons.span-mode-detour.md`：1 則，最新一則「先卡住了。」（updated_at 2026-09-12T00:00:00+08:00）
EOF
OUTPUT="$(echo '{"source":"clear"}' | bash "$SCRIPT_DIR/session-start-devlog.sh" 2>&1)"
if [ -z "$OUTPUT" ]; then
  echo "PASS: source=clear stays silent even with a Lessons 索引 block present"
else
  echo "FAIL: source=clear must not inject anything, got: $OUTPUT"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
