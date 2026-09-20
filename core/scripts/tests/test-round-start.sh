#!/usr/bin/env bash
# Self-check for round-start.sh skeleton + dangling heal. Run:
#   bash hooks/scripts/test-round-start.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../json-field.sh
. "$SCRIPT_DIR/json-field.sh"
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
BODY="$(cat "$DEVLOG_DIR/.round-current.md")"
assert_contains "Round 1 heading" "## Round 1 —" "$BODY"
assert_contains "fenced user input" $'```text\nhello world\n```' "$BODY"
assert_contains "status in progress" $'### Status\nIN_PROGRESS' "$BODY"
assert_file_absent "Round 1 skeleton -> devlog.md untouched" "$DEVLOG_DIR/devlog.md"
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
AFTER_HASH="$(cksum < "$DEVLOG_DIR/.round-current.md")"
START_HASH="$(cat "$DEVLOG_DIR/.turn-start")"
if [ "$AFTER_HASH" = "$START_HASH" ]; then
  echo "PASS: .turn-start matches post-skeleton hash"
else
  echo "FAIL: .turn-start should be captured after skeleton write"
  FAIL=1
fi

# --- 2b: normal (non-fold) new-round path writes to .round-current.md,
# leaving devlog.md's prior history untouched, and .turn-start hashes
# .round-current.md -----------------------------------------------------
NEW_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$NEW_DIR"
mkdir -p "$NEW_DIR/.devlog"
touch "$NEW_DIR/.devlog/.enabled"
printf '## Round 3 — 2026-09-17T08:00:00+0800\n\n### Summary\ns3\n\n### Handoff\n#### 現況\nc3\n\n### Status\nDONE\n' > "$NEW_DIR/.devlog/devlog.md"

echo '{"session_id":"s2","prompt":"下一件事"}' | bash "$SCRIPT_DIR/round-start.sh"

MAIN_AFTER="$(cat "$NEW_DIR/.devlog/devlog.md")"
CURRENT_AFTER="$(cat "$NEW_DIR/.devlog/.round-current.md" 2>/dev/null || echo '')"
assert_not_contains "new round: not appended to devlog.md directly" "## Round 4" "$MAIN_AFTER"
assert_contains "new round: skeleton written to .round-current.md" "## Round 4" "$CURRENT_AFTER"
assert_contains "new round: devlog.md keeps prior history" "## Round 3" "$MAIN_AFTER"

TURN_HASH="$(cat "$NEW_DIR/.devlog/.turn-start" 2>/dev/null || echo '')"
EXPECTED_HASH="$(cksum < "$NEW_DIR/.devlog/.round-current.md")"
if [ "$TURN_HASH" = "$EXPECTED_HASH" ]; then echo "PASS: .turn-start hashes .round-current.md"; else echo "FAIL: .turn-start hashes .round-current.md"; FAIL=1; fi
rm -rf "$NEW_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

# --- 3: next prompt is Round 2 (dangling heal stamps devlog.md; the new
# round opens in .round-current.md) — a genuinely-open Round 1 sitting in
# .round-current.md is a hand-built fixture representing what
# close-open-round.sh operates on ------------------------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.round-current.md"
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello world
```
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
printf '%s' '{"prompt":"second"}' | bash "$SCRIPT_DIR/round-start.sh"
MAIN_BODY="$(cat "$DEVLOG_DIR/devlog.md")"
CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
assert_contains "Round 2 heading in .round-current.md" "## Round 2 —" "$CUR_BODY"
assert_contains "previous round interrupted (dangling heal) in devlog.md" "INTERRUPTED" "$MAIN_BODY"
assert_contains "dangling reason" "dangling:next_prompt" "$MAIN_BODY"
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
BODY="$(cat "$DEVLOG_DIR/.round-current.md")"
assert_contains "placeholder prompt" "（無 prompt）" "$BODY"

# --- 7a: inner fence neutralized before wrapping ----------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
printf '%s' '{"prompt":"before```inside```after"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/.round-current.md")"
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
BODY="$(cat "$DEVLOG_DIR/.round-current.md")"
assert_contains "prompt token masked" "（已遮罩）" "$BODY"
assert_not_contains "raw prompt token absent" "$RAW_TOKEN" "$BODY"

# --- 7b: truncation notice when prompt exceeds 4000 -------------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
LONG="$(awk 'BEGIN { s=""; for (i=0;i<4005;i++) s=s "a"; print s }')"
printf '{"prompt":"%s"}' "$LONG" | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/.round-current.md")"
assert_contains "truncation notice" "（後略，已截斷至 4000 字）" "$BODY"
LEN="$(awk '/^```text$/{p=1;next} /^```$/{p=0;next} p{s=s $0} END{print length(s)}' "$DEVLOG_DIR/.round-current.md")"
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
UNFENCED="$(awk '/^[ \t]*```/{f=!f} !f && /^## Round /{c++} END{print c+0}' "$DEVLOG_DIR/.round-current.md")"
if [ "$UNFENCED" = "1" ]; then
  echo "PASS: prompt ## Round 99 did not create a second unfenced Round heading"
else
  echo "FAIL: expected 1 unfenced ## Round heading, got $UNFENCED"
  FAIL=1
fi

# --- 9: segment last_seen_cksum is post-skeleton, tracking .round-current.md
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open"
printf '%s\n' '{"last_change_epoch": 1, "last_seen_cksum": "old", "max_silent_seconds": 900}' > "$DEVLOG_DIR/.segment-state"
printf '%s' "$PROMPT_HELLO" | bash "$SCRIPT_DIR/round-start.sh"
POST="$(cksum < "$DEVLOG_DIR/.round-current.md" | tr -d '\n')"
SEEN="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
if [ "$SEEN" = "$POST" ]; then
  echo "PASS: segment last_seen_cksum matches post-skeleton hash"
else
  echo "FAIL: last_seen_cksum=$SEEN expected $POST"
  FAIL=1
fi

# --- 9c: segment-state cksum identity tracks .round-current.md, in isolation
SEG_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$SEG_DIR"
mkdir -p "$SEG_DIR/.devlog"
touch "$SEG_DIR/.devlog/.enabled"
printf '{"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 600}\n' > "$SEG_DIR/.devlog/.segment-state"

echo '{"session_id":"s3","prompt":"go"}' | bash "$SCRIPT_DIR/round-start.sh"

STORED_CKSUM="$(json_str_get "$SEG_DIR/.devlog/.segment-state" last_seen_cksum)"
ACTUAL_CKSUM="$(cksum < "$SEG_DIR/.devlog/.round-current.md" | tr -d '\n')"
if [ "$STORED_CKSUM" = "$ACTUAL_CKSUM" ]; then echo "PASS: segment-state cksum tracks .round-current.md"; else echo "FAIL: segment-state cksum tracks .round-current.md (got $STORED_CKSUM want $ACTUAL_CKSUM)"; FAIL=1; fi
rm -rf "$SEG_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

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
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.round-current.md"
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
done
```

### Summary
finished

### Reply
fixture reply.

### Handoff
#### 現況
finished

### Status
DONE
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/.round-current.md" > "$DEVLOG_DIR/.turn-start"
printf '\n' >> "$DEVLOG_DIR/.round-current.md"
printf '%s' '{"prompt":"next"}' | bash "$SCRIPT_DIR/round-start.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
assert_contains "completed dangling keeps DONE" $'### Status\nDONE' "$BODY"
assert_not_contains "completed dangling must not stamp Round 1" "INTERRUPTED" "$BODY"
assert_contains "still opened Round 2" "## Round 2 —" "$CUR_BODY"

# --- 11: .awaiting-reply matches last Round -> folds as a segment, reopening
# the Round out of devlog.md and into .round-current.md --------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.span-open" "$DEVLOG_DIR/.checkpoint-state" "$DEVLOG_DIR/.round-current.md"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 5 — 2026-09-09T12:00:00+08:00

### User Input
```text
what color should the button be?
```

### Summary
Asked the user to pick a color.

### Reply
fixture reply.

### Handoff
#### 現況
Waiting on the user's color choice.
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
#### 下一步
Apply the chosen color once they answer.

### Status
BLOCKED
EOF
printf '%s\n' '{"round": 5, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"blue please"}' | bash "$SCRIPT_DIR/round-start.sh"
MAIN_BODY="$(cat "$DEVLOG_DIR/devlog.md" 2>/dev/null || echo '')"
CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
assert_not_contains "fold: round 5 no longer in devlog.md" "## Round 5" "$MAIN_BODY"
UNFENCED_ROUNDS="$(awk '/^[ \t]*```/{f=!f} !f && /^## Round /{c++} END{print c+0}' "$DEVLOG_DIR/.round-current.md")"
if [ "$UNFENCED_ROUNDS" = "1" ]; then
  echo "PASS: fold did not open a second Round"
else
  echo "FAIL: expected 1 unfenced Round heading, got $UNFENCED_ROUNDS"
  FAIL=1
fi
assert_contains "folded segment heading" "### 段落 1 -" "$CUR_BODY"
assert_contains "folded segment marks it a reply" "（回覆上一輪的問題）" "$CUR_BODY"
assert_contains "folded segment keeps user's words" "blue please" "$CUR_BODY"
# segment must land before Summary, not after
SEG_LINE="$(grep -n '### 段落 1' "$DEVLOG_DIR/.round-current.md" | head -1 | cut -d: -f1)"
SUM_LINE="$(grep -n '^### Summary$' "$DEVLOG_DIR/.round-current.md" | head -1 | cut -d: -f1)"
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
AFTER_HASH="$(cksum < "$DEVLOG_DIR/.round-current.md")"
START_HASH="$(cat "$DEVLOG_DIR/.turn-start")"
if [ "$AFTER_HASH" = "$START_HASH" ]; then
  echo "PASS: .turn-start matches post-fold hash"
else
  echo "FAIL: .turn-start should be captured after the fold insert"
  FAIL=1
fi

# --- 11b (Step 3 brief test): Reply Fold reopens the awaited round into
# .round-current.md, not editing it in place inside devlog.md — devlog.md
# should no longer contain it, and .round-current.md should hold exactly
# that round plus the folded segment. Own isolated fixture. --------------
FOLD_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$FOLD_DIR"
mkdir -p "$FOLD_DIR/.devlog"
touch "$FOLD_DIR/.devlog/.enabled"
printf '## Round 5 — 2026-09-17T09:00:00+0800\n\n### User Input\n```text\n要不要修 A？\n```\n\n### Summary\n問了一題\n\n### Handoff\n#### 現況\n等回覆\n\n### Status\nBLOCKED\n' > "$FOLD_DIR/.devlog/devlog.md"
printf '{"round": 5}\n' > "$FOLD_DIR/.devlog/.awaiting-reply"

echo '{"session_id":"s1","prompt":"要"}' | bash "$SCRIPT_DIR/round-start.sh"

MAIN_AFTER="$(cat "$FOLD_DIR/.devlog/devlog.md")"
CURRENT_AFTER="$(cat "$FOLD_DIR/.devlog/.round-current.md" 2>/dev/null || echo '')"
assert_not_contains "fold: round 5 no longer in devlog.md" "## Round 5" "$MAIN_AFTER"
assert_contains "fold: round 5 moved into .round-current.md" "## Round 5" "$CURRENT_AFTER"
assert_contains "fold: folded segment written into .round-current.md" "回覆上一輪的問題" "$CURRENT_AFTER"
rm -rf "$FOLD_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

# --- 12: second reply on the same Round numbers segments incrementally,
# standalone fixture: devlog.md holds the round already folded once
# (matching the merged-back-between-turns invariant) -----------------------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.round-current.md"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 5 — 2026-09-09T12:00:00+08:00

### User Input
```text
what color should the button be?
```

### 段落 1 - 12:01（回覆上一輪的問題）
```text
blue please
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
printf '%s\n' '{"round": 5, "opened_at": "2026-09-09T12:05:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"actually make it green"}' | bash "$SCRIPT_DIR/round-start.sh"
CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
assert_contains "first segment still present" "### 段落 1 -" "$CUR_BODY"
assert_contains "second segment numbered 2" "### 段落 2 -" "$CUR_BODY"
assert_contains "second segment content" "actually make it green" "$CUR_BODY"

# --- 13: .awaiting-reply round is stale -> dropped, normal new Round opens -
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.round-current.md"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

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
printf '%s\n' '{"round": 99, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.awaiting-reply"
printf '%s' '{"prompt":"unrelated new request"}' | bash "$SCRIPT_DIR/round-start.sh"
CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
assert_contains "stale marker -> normal new Round 2 opened" "## Round 2 —" "$CUR_BODY"
assert_not_contains "stale marker -> no segment inserted" "### 段落" "$CUR_BODY"
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

### Reply
fixture reply.

### Handoff
#### 現況
running
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
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

### Reply
fixture reply.

### Handoff
#### 現況
waiting on reply
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
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

# --- 16: task-notification prompt folds into the last Round, condensed -----
NOTIF_PROMPT='<task-notification><task-id>t1</task-id><status>completed</status><summary>Agent \"Fix wave\" finished</summary></task-notification>'
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.checkpoint-state" "$DEVLOG_DIR/.round-current.md"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 7 — 2026-09-09T12:00:00+08:00

### User Input
```text
refactor the widget module
```

### Summary
Refactored the widget module.

### Reply
fixture reply.

### Handoff
#### 現況
Done, tests pass.

### Status
DONE
EOF
printf '%s\n' '{"rounds_since_checkpoint": 0, "max_silent_rounds": 20, "checkpoint_marker_count": 0}' > "$DEVLOG_DIR/.checkpoint-state"
printf '{"prompt":"%s"}' "$NOTIF_PROMPT" | bash "$SCRIPT_DIR/round-start.sh"
CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
UNFENCED_ROUNDS="$(awk '/^[ \t]*```/{f=!f} !f && /^## Round /{c++} END{print c+0}' "$DEVLOG_DIR/.round-current.md")"
if [ "$UNFENCED_ROUNDS" = "1" ]; then
  echo "PASS: task-notification did not open a second Round"
else
  echo "FAIL: expected 1 unfenced Round heading, got $UNFENCED_ROUNDS"
  FAIL=1
fi
assert_contains "task-notification segment heading" "### 段落 1 -" "$CUR_BODY"
assert_contains "task-notification segment marked as background" "（背景任務通知）" "$CUR_BODY"
assert_contains "task-notification segment keeps the condensed summary" 'Agent "Fix wave" finished' "$CUR_BODY"
assert_contains "task-notification segment keeps status" "status=completed" "$CUR_BODY"
assert_contains "task-notification segment keeps task-id" "task-id=t1" "$CUR_BODY"
assert_not_contains "task-notification raw tag not recorded" "<task-notification>" "$CUR_BODY"
SEG_LINE="$(grep -n '### 段落 1' "$DEVLOG_DIR/.round-current.md" | head -1 | cut -d: -f1)"
SUM_LINE="$(grep -n '^### Summary$' "$DEVLOG_DIR/.round-current.md" | head -1 | cut -d: -f1)"
if [ "$SEG_LINE" -lt "$SUM_LINE" ]; then
  echo "PASS: task-notification segment inserted before Summary"
else
  echo "FAIL: task-notification segment landed after Summary (seg=$SEG_LINE summary=$SUM_LINE)"
  FAIL=1
fi
OPEN_N="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.round-open" | grep -o '[0-9]\+$')"
if [ "$OPEN_N" = "7" ]; then
  echo "PASS: .round-open reopened to the folded Round (7)"
else
  echo "FAIL: expected .round-open round=7, got $OPEN_N"
  FAIL=1
fi
CP="$(grep -o '"rounds_since_checkpoint"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.checkpoint-state" | grep -o '[0-9]\+$')"
if [ "$CP" = "0" ]; then
  echo "PASS: task-notification fold does not increment rounds_since_checkpoint"
else
  echo "FAIL: expected rounds_since_checkpoint to stay 0, got $CP"
  FAIL=1
fi
rm -f "$DEVLOG_DIR/.checkpoint-state"

# --- 17: task-notification with no existing Round opens one, still condensed
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start" "$DEVLOG_DIR/.round-current.md"
printf '{"prompt":"%s"}' "$NOTIF_PROMPT" | bash "$SCRIPT_DIR/round-start.sh"
CUR_BODY="$(cat "$DEVLOG_DIR/.round-current.md" 2>/dev/null || echo '')"
assert_contains "fresh task-notification opens Round 1" "## Round 1 —" "$CUR_BODY"
assert_contains "fresh task-notification condensed summary" 'Agent "Fix wave" finished' "$CUR_BODY"
assert_not_contains "fresh task-notification raw tag not recorded" "<task-notification>" "$CUR_BODY"

# --- 18: task-notification during an open span is still suppressed ---------
rm -f "$DEVLOG_DIR/devlog.md" "$DEVLOG_DIR/.round-open" "$DEVLOG_DIR/.turn-start"
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00", "ticks_since_checkin": 0, "max_silent_ticks": 5}' > "$DEVLOG_DIR/.span-open"
printf '{"prompt":"%s"}' "$NOTIF_PROMPT" | bash "$SCRIPT_DIR/round-start.sh"
if [ -f "$DEVLOG_DIR/devlog.md" ]; then
  echo "FAIL: task-notification during open span should not create devlog.md"
  FAIL=1
else
  echo "PASS: task-notification during open span created no devlog.md"
fi
assert_file_absent "task-notification during open span: no .round-open" "$DEVLOG_DIR/.round-open"
rm -f "$DEVLOG_DIR/.span-open"

# --- workspace claim on next prompt ----------------------------------------
WS="$TMP_ROOT/ws"
mkdir -p "$WS/.devlog"
export CLAUDE_PROJECT_DIR="$WS"
touch "$WS/.devlog/.enabled"
git -C "$WS" init -q -b main
git -C "$WS" config user.email test@example.com
git -C "$WS" config user.name test
echo hello > "$WS/a.txt"
git -C "$WS" add a.txt
git -C "$WS" commit -q -m init
LIVE="$(bash "$SCRIPT_DIR/workspace-snapshot.sh" "$WS")"
cat > "$WS/.devlog/devlog.md" <<EOF
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 工作區
${LIVE}
#### 現況
going
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
do x

### Status
IN_PROGRESS
EOF
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
[ -z "$OUT" ] && echo "PASS: matching 工作區 prints nothing" || { echo "FAIL: match stdout [$OUT]"; FAIL=1; }
[ ! -f "$WS/.devlog/.workspace-mismatch" ] && echo "PASS: matching 工作區 writes no marker" || { echo "FAIL: marker on match"; FAIL=1; }
grep -q '^## Round 2' "$WS/.devlog/.round-current.md" && echo "PASS: still opened Round 2" || { echo "FAIL: no round 2"; FAIL=1; }

rm -f "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md"
# This fixture is reused below by the drift-only counter assertions (1 -> 2 ->
# reset-at-3). Its ### Status must stay non-BLOCKED: if it were BLOCKED, the
# BLOCKED-round bump would also fire on the same invocation and double-count
# the shared counter, breaking those assertions with a confusing failure.
cat > "$WS/.devlog/devlog.md" <<EOF
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨
#### 現況
going
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
do x

### Status
IN_PROGRESS
EOF
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_contains "mismatch stdout names 工作區" "#### 工作區" "$OUT"
assert_contains "mismatch stdout has 宣稱" "宣稱：" "$OUT"
assert_contains "mismatch stdout has 實際" "實際：" "$OUT"
assert_contains "mismatch stdout has live snapshot" "$LIVE" "$OUT"
[ -f "$WS/.devlog/.workspace-mismatch" ] && echo "PASS: mismatch writes marker" || { echo "FAIL: no marker"; FAIL=1; }
MARKER="$(cat "$WS/.devlog/.workspace-mismatch")"
[ "$MARKER" = "$LIVE" ] && echo "PASS: marker is live snapshot" || { echo "FAIL: marker [$MARKER]"; FAIL=1; }

# --- lessons drift counter: mechanical nudge on repeated mismatch --------
rm -f "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md" "$WS/.devlog/.workspace-mismatch"
touch "$WS/.devlog/.lessons-enabled"
printf '%s\n' '{"count": 0, "threshold": 3}' > "$WS/.devlog/.lessons-advisory-state"

OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_not_contains "drift count 1/3: no nudge yet" "[Lessons Mode 提示]" "$OUT"
grep -q '"count": 1' "$WS/.devlog/.lessons-advisory-state" && echo "PASS: drift count -> 1" || { echo "FAIL: drift count not 1"; FAIL=1; }

rm -f "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md"
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_not_contains "drift count 2/3: no nudge yet" "[Lessons Mode 提示]" "$OUT"
grep -q '"count": 2' "$WS/.devlog/.lessons-advisory-state" && echo "PASS: drift count -> 2" || { echo "FAIL: drift count not 2"; FAIL=1; }

rm -f "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md"
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_contains "drift count hits threshold: prints nudge" "[Lessons Mode 提示]" "$OUT"
grep -q '"count": 0' "$WS/.devlog/.lessons-advisory-state" && echo "PASS: drift count reset after nudge" || { echo "FAIL: drift count not reset"; FAIL=1; }

# without .lessons-enabled: no counting, no nudge, state file untouched
rm -f "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md" "$WS/.devlog/.lessons-enabled"
printf '%s\n' '{"count": 2, "threshold": 3}' > "$WS/.devlog/.lessons-advisory-state"
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_not_contains "lessons off: no nudge even near threshold" "[Lessons Mode 提示]" "$OUT"
grep -q '"count": 2' "$WS/.devlog/.lessons-advisory-state" && echo "PASS: drift count untouched when lessons off" || { echo "FAIL: drift count changed when lessons off"; FAIL=1; }
rm -f "$WS/.devlog/.lessons-advisory-state" "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md"

# --- lessons drift counter: upgrade path — .lessons-enabled exists (from
# before this branch) but .lessons-advisory-state was never created. round-start.sh
# must create it with defaults and still act on this same invocation's
# mismatch, not require a second message ------------------------------------
rm -f "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md" "$WS/.devlog/.workspace-mismatch" "$WS/.devlog/.lessons-advisory-state"
touch "$WS/.devlog/.lessons-enabled"
cat > "$WS/.devlog/devlog.md" <<EOF
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨
#### 現況
going
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
do x

### Status
IN_PROGRESS
EOF
OUT="$(printf '%s' '{"prompt":"keep going"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
[ -f "$WS/.devlog/.lessons-advisory-state" ] && echo "PASS: upgrade path creates .lessons-advisory-state on first drift" || { echo "FAIL: .lessons-advisory-state not created for pre-existing lessons-enabled"; FAIL=1; }
grep -q '"count": 1' "$WS/.devlog/.lessons-advisory-state" 2>/dev/null && echo "PASS: newly-created state already counted this invocation's mismatch (1)" || { echo "FAIL: count not 1 in newly-created state"; FAIL=1; }
grep -q '"threshold": 3' "$WS/.devlog/.lessons-advisory-state" 2>/dev/null && echo "PASS: newly-created state has default threshold 3" || { echo "FAIL: threshold not 3 in newly-created state"; FAIL=1; }
assert_not_contains "upgrade path: no nudge yet on first-ever drift (1 < 3)" "[Lessons Mode 提示]" "$OUT"
rm -f "$WS/.devlog/.round-open" "$WS/.devlog/.round-current.md" "$WS/.devlog/.lessons-enabled" "$WS/.devlog/.lessons-advisory-state"

cat > "$WS/.devlog/devlog.md" <<EOF
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨

### Status
DONE
EOF
rm -f "$WS/.devlog/.workspace-mismatch"
OUT="$(printf '%s' '{"prompt":"new topic"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
[ -z "$OUT" ] && echo "PASS: DONE prints nothing" || { echo "FAIL: DONE stdout [$OUT]"; FAIL=1; }
[ ! -f "$WS/.devlog/.workspace-mismatch" ] && echo "PASS: DONE writes no marker" || { echo "FAIL: DONE marker"; FAIL=1; }

cat > "$WS/.devlog/devlog.md" <<EOF
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨
#### 現況
going
#### 完成條件
`bash hooks/scripts/tests/test-enforce-devlog.sh` 相關情境通過。
#### 下一步
do x

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "ticks_since_checkin": 0, "max_silent_ticks": 5}' > "$WS/.devlog/.span-open"
rm -f "$WS/.devlog/.workspace-mismatch"
printf '%s' '{"prompt":"tick"}' | bash "$SCRIPT_DIR/round-start.sh" >/dev/null
[ ! -f "$WS/.devlog/.workspace-mismatch" ] && echo "PASS: span skip writes no marker" || { echo "FAIL: span marker"; FAIL=1; }
rm -f "$WS/.devlog/.span-open"

# --- BLOCKED-round accumulation shares the advisory counter -----------------
BLK_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$BLK_DIR"
mkdir -p "$BLK_DIR/.devlog"
touch "$BLK_DIR/.devlog/.enabled" "$BLK_DIR/.devlog/.lessons-enabled"
printf '%s\n' '{"count": 0, "threshold": 3}' > "$BLK_DIR/.devlog/.lessons-advisory-state"
cat > "$BLK_DIR/.devlog/devlog.md" <<'EOF'
## Round 1 — 2026-09-20T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 現況
waiting
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
#### 下一步
apply the answer

### Status
BLOCKED
EOF
OUT="$(printf '%s' '{"prompt":"next"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_not_contains "BLOCKED round 1/3: no advisory yet" "[Lessons Mode 提示]" "$OUT"
grep -q '"count": 1' "$BLK_DIR/.devlog/.lessons-advisory-state" && echo "PASS: BLOCKED round bumped counter to 1" || { echo "FAIL: counter not bumped to 1"; FAIL=1; }

rm -f "$BLK_DIR/.devlog/.round-open" "$BLK_DIR/.devlog/.round-current.md"
cat >> "$BLK_DIR/.devlog/devlog.md" <<'EOF'

## Round 2 — 2026-09-20T00:05:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 現況
waiting
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
#### 下一步
apply the answer

### Status
BLOCKED
EOF
OUT="$(printf '%s' '{"prompt":"next again"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_not_contains "BLOCKED round 2/3: no advisory yet" "[Lessons Mode 提示]" "$OUT"
grep -q '"count": 2' "$BLK_DIR/.devlog/.lessons-advisory-state" && echo "PASS: BLOCKED round bumped counter to 2" || { echo "FAIL: counter not bumped to 2"; FAIL=1; }

rm -f "$BLK_DIR/.devlog/.round-open" "$BLK_DIR/.devlog/.round-current.md"
cat >> "$BLK_DIR/.devlog/devlog.md" <<'EOF'

## Round 3 — 2026-09-20T00:10:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 現況
waiting
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
#### 下一步
apply the answer

### Status
BLOCKED
EOF
OUT="$(printf '%s' '{"prompt":"next once more"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_contains "BLOCKED round 3/3: hits threshold" "[Lessons Mode 提示]" "$OUT"
grep -q '"count": 0' "$BLK_DIR/.devlog/.lessons-advisory-state" && echo "PASS: counter reset after threshold" || { echo "FAIL: counter not reset"; FAIL=1; }
rm -rf "$BLK_DIR"

# --- BLOCKED->resolved: mechanical, one-shot print, not counted -------------
RES_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$RES_DIR"
mkdir -p "$RES_DIR/.devlog"
touch "$RES_DIR/.devlog/.enabled" "$RES_DIR/.devlog/.lessons-enabled"
cat > "$RES_DIR/.devlog/devlog.md" <<'EOF'
## Round 1 — 2026-09-20T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 現況
waiting
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
#### 下一步
apply the answer

### Status
BLOCKED

## Round 2 — 2026-09-20T00:05:00+08:00

### Summary
resolved it

### Reply
fixture reply.

### Handoff
#### 現況
done

### Status
DONE
EOF
OUT="$(printf '%s' '{"prompt":"whats next"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_contains "BLOCKED->resolved prints a one-shot advisory" "上一輪從 BLOCKED 解開了" "$OUT"
[ ! -f "$RES_DIR/.devlog/.lessons-advisory-state" ] && echo "PASS: resolved-transition print does not touch the shared counter" || { echo "FAIL: resolved-transition print created/touched the counter file"; FAIL=1; }

# resolved print requires two rounds of history: with only one round of
# history (regardless of its own status) there's no "second-to-last" round
# to compare against.
rm -rf "$RES_DIR"
RES2_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$RES2_DIR"
mkdir -p "$RES2_DIR/.devlog"
touch "$RES2_DIR/.devlog/.enabled" "$RES2_DIR/.devlog/.lessons-enabled"
cat > "$RES2_DIR/.devlog/devlog.md" <<'EOF'
## Round 1 — 2026-09-20T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 現況
done

### Status
DONE
EOF
OUT="$(printf '%s' '{"prompt":"go"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_not_contains "cold start (one round of history): no resolved print" "上一輪從 BLOCKED 解開了" "$OUT"
rm -rf "$RES2_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

# --- without .lessons-enabled: BLOCKED accumulation does not run at all ----
NOLES_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$NOLES_DIR"
mkdir -p "$NOLES_DIR/.devlog"
touch "$NOLES_DIR/.devlog/.enabled"
cat > "$NOLES_DIR/.devlog/devlog.md" <<'EOF'
## Round 1 — 2026-09-20T00:00:00+08:00

### Summary
s

### Reply
fixture reply.

### Handoff
#### 現況
waiting
#### 完成條件
缺的外部輸入已出現，且可觀察條件達成。
#### 下一步
apply the answer

### Status
BLOCKED
EOF
OUT="$(printf '%s' '{"prompt":"next"}' | bash "$SCRIPT_DIR/round-start.sh" 2>/dev/null)"
assert_not_contains "lessons off: no BLOCKED-accumulation advisory" "[Lessons Mode 提示]" "$OUT"
[ ! -f "$NOLES_DIR/.devlog/.lessons-advisory-state" ] && echo "PASS: lessons off leaves no advisory-state file" || { echo "FAIL: advisory-state file created while lessons off"; FAIL=1; }
rm -rf "$NOLES_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
