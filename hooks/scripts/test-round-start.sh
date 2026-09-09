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
assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $desc (unexpected: $needle)"; FAIL=1 ;;
    *) echo "PASS: $desc" ;;
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

# --- 7aa: common provider tokens are masked in User Input -------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
RAW_TOKEN="ghp_abcdefghijklmnopqrstuvwxyz0123456789"
printf '{"prompt":"token %s"}' "$RAW_TOKEN" | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "prompt token masked" "（已遮罩）" "$BODY"
assert_not_contains "raw prompt token absent" "$RAW_TOKEN" "$BODY"

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

# --- 9b: segment state stores the submitting session id ---------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
printf '%s\n' '{"last_change_epoch": 1, "last_seen_cksum": "old", "max_silent_seconds": 900}' > "$DEVLOG_DIR/.segment-state"
printf '%s' '{"prompt":"hi","session_id":"s1"}' | bash "$SCRIPT_DIR/round-start.sh"
SESSION_ID="$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
if [ "$SESSION_ID" = "s1" ]; then
  echo "PASS: segment state stores session_id"
else
  echo "FAIL: expected session_id=s1, got [$SESSION_ID]"
  FAIL=1
fi

# --- 10: dangling heal skips a completed last Round, still opens Round 2 ----
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.span-open"
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
printf '%s' '{"prompt":"next"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "completed dangling keeps DONE" $'### Status\nDONE' "$BODY"
assert_not_contains "completed dangling must not stamp Round 1" "INTERRUPTED" "$BODY"
assert_contains "still opened Round 2" "## Round 2 —" "$BODY"

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

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
