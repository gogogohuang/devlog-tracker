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

# --- 5: no .round-open -> delete .interrupted, do not edit devlog -----------
write_skeleton
rm -f "$DEVLOG_DIR/.round-open"
touch "$DEVLOG_DIR/.interrupted"
BEFORE="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:other"
AFTER="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: missing .round-open -> devlog unchanged"
else
  echo "FAIL: missing .round-open edited the file"
  FAIL=1
fi
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: missing .round-open should still delete .interrupted"
  FAIL=1
else
  echo "PASS: missing .round-open deleted .interrupted"
fi

# --- 5b: malformed .round-open -> delete .interrupted, do not edit ---------
write_skeleton
printf '%s\n' 'not valid json' > "$DEVLOG_DIR/.round-open"
touch "$DEVLOG_DIR/.interrupted"
BEFORE="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:other"
AFTER="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: malformed .round-open -> devlog unchanged"
else
  echo "FAIL: malformed .round-open edited the file"
  FAIL=1
fi
if [ -f "$DEVLOG_DIR/.interrupted" ] || [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: malformed .round-open should delete both markers"
  FAIL=1
else
  echo "PASS: malformed .round-open deleted both markers"
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
