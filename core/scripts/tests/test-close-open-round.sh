#!/usr/bin/env bash
# Self-check for close-open-round.sh. Run:
#   bash hooks/scripts/test-close-open-round.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
assert_file_absent() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "FAIL: $desc (file still present: $path)"
    FAIL=1
  else
    echo "PASS: $desc"
  fi
}

write_skeleton() {
  : > "$DEVLOG_DIR/devlog.md"
  cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
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

# --- 1: no .enabled -> no-op, .round-current.md untouched -------------------
rm -f "$DEVLOG_DIR/.enabled"
write_skeleton
BEFORE="$(cat "$DEVLOG_DIR/.round-current.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "dangling:next_prompt"
assert_exit "no .enabled -> exit 0" 0 $?
AFTER="$(cat "$DEVLOG_DIR/.round-current.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: no .enabled -> .round-current.md unchanged"
else
  echo "FAIL: no .enabled should not edit .round-current.md"
  FAIL=1
fi
touch "$DEVLOG_DIR/.enabled"

# --- 2: matching skeleton, never touched (not recovered) -> INTERRUPTED +
#        "no record left" stub wording, merged into devlog.md, markers gone -
write_skeleton
touch "$DEVLOG_DIR/.interrupted"
bash "$SCRIPT_DIR/close-open-round.sh" "StopFailure:server_error"
assert_exit "matching open round -> exit 0" 0 $?
assert_file_absent "stamp: .round-current.md removed after merge" "$DEVLOG_DIR/.round-current.md"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "status INTERRUPTED" $'### Status\nINTERRUPTED' "$BODY"
assert_contains "reason line" "StopFailure:server_error" "$BODY"
assert_contains "summary stub (not recovered)" "devlog.md 沒有留下任何後續處理紀錄就結束了" "$BODY"
assert_contains "handoff stub heading" "#### 現況" "$BODY"
assert_contains "handoff stub body (not recovered)" "這一輪沒有留下任何處理紀錄" "$BODY"
assert_contains "user input kept" "hello" "$BODY"

# --- 2b: skeleton + a segment was recorded (recovered) but Summary/Handoff
#         still missing -> INTERRUPTED + the old "interrupted mid-way" stub --
write_skeleton
cksum < "$DEVLOG_DIR/devlog.md" > "$DEVLOG_DIR/.turn-start"
printf '\n### 段落 1 - 12:01\n```text\nsome progress\n```\n\n' >> "$DEVLOG_DIR/devlog.md"
bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "recovered summary stub" "這輪意外中斷。" "$BODY"
assert_contains "recovered handoff stub" "這輪沒有正常收尾。" "$BODY"
assert_contains "recovered segment kept" "some progress" "$BODY"
if [ -f "$DEVLOG_DIR/.round-open" ] || [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: markers should be deleted after a successful stamp"
  FAIL=1
else
  echo "PASS: .round-open and .interrupted deleted"
fi

# --- 3: already has headings -> do not duplicate stubs, still stamp+merge ---
: > "$DEVLOG_DIR/devlog.md"
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello
```

### Summary
partial

### Reply
fixture reply.

### Handoff
#### 現況
partial

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
rm -f "$DEVLOG_DIR/.turn-start"
bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt"
assert_file_absent "existing-headings: .round-current.md removed after merge" "$DEVLOG_DIR/.round-current.md"
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

# --- 4: no .round-open -> delete .interrupted, do not touch either file -----
write_skeleton
rm -f "$DEVLOG_DIR/.round-open"
touch "$DEVLOG_DIR/.interrupted"
BEFORE_CUR="$(cat "$DEVLOG_DIR/.round-current.md")"
BEFORE_MAIN="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:other"
AFTER_CUR="$(cat "$DEVLOG_DIR/.round-current.md")"
AFTER_MAIN="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE_CUR" = "$AFTER_CUR" ] && [ "$BEFORE_MAIN" = "$AFTER_MAIN" ]; then
  echo "PASS: missing .round-open -> nothing merged or edited"
else
  echo "FAIL: missing .round-open touched a file"
  FAIL=1
fi
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: missing .round-open should still delete .interrupted"
  FAIL=1
else
  echo "PASS: missing .round-open deleted .interrupted"
fi
rm -f "$DEVLOG_DIR/.round-current.md"

# --- 4b: malformed .round-open -> delete both markers, do not touch either --
write_skeleton
printf '%s\n' 'not valid json' > "$DEVLOG_DIR/.round-open"
touch "$DEVLOG_DIR/.interrupted"
BEFORE_CUR="$(cat "$DEVLOG_DIR/.round-current.md")"
BEFORE_MAIN="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:other"
AFTER_CUR="$(cat "$DEVLOG_DIR/.round-current.md")"
AFTER_MAIN="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE_CUR" = "$AFTER_CUR" ] && [ "$BEFORE_MAIN" = "$AFTER_MAIN" ]; then
  echo "PASS: malformed .round-open -> nothing merged or edited"
else
  echo "FAIL: malformed .round-open touched a file"
  FAIL=1
fi
if [ -f "$DEVLOG_DIR/.interrupted" ] || [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: malformed .round-open should delete both markers"
  FAIL=1
else
  echo "PASS: malformed .round-open deleted both markers"
fi
rm -f "$DEVLOG_DIR/.round-current.md"

# --- 5: prior finished history in devlog.md is preserved across the merge --
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T11:00:00+08:00

### Summary
old

### Reply
fixture reply.

### Handoff
#### 現況
old

### Status
DONE

## Checkpoint（Round 1 摘要）
keep me
EOF
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 2 — 2026-09-09T12:00:00+08:00

### User Input
```text
new
```

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 2, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:clear"
assert_file_absent "prior-history: .round-current.md removed after merge" "$DEVLOG_DIR/.round-current.md"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "round 1 stays DONE" $'### Status\nDONE' "$BODY"
assert_contains "round 2 interrupted" "INTERRUPTED" "$BODY"
assert_contains "checkpoint kept" "keep me" "$BODY"

# --- 6: headings present but hash equal -> still stamp (no recovery proof) --
# (main's independent "completed last Round + hash moved -> do not stamp"
# fixture, which asserted devlog.md stayed byte-for-byte unchanged, tested a
# pre-merge assumption this branch deliberately changes: a recovered round
# now always gets merged into devlog.md rather than left in place untouched.
# That property is covered below by scenario 8 ("recovered case also
# merges"), which asserts the merge instead of asserting no-op.)
: > "$DEVLOG_DIR/devlog.md"
cat > "$DEVLOG_DIR/.round-current.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### User Input
```text
hello
```

### Summary
partial

### Reply
fixture reply.

### Handoff
#### 現況
partial

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 1, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
cksum < "$DEVLOG_DIR/.round-current.md" > "$DEVLOG_DIR/.turn-start"
bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt"
assert_file_absent "hash-equal: .round-current.md removed after merge" "$DEVLOG_DIR/.round-current.md"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "hash-equal headings still stamp" "INTERRUPTED" "$BODY"
assert_contains "hash-equal reason" "user_interrupt" "$BODY"

# --- 7: stamp-then-merge, prior round in devlog.md preserved ---------------
STAMP_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$STAMP_DIR"
mkdir -p "$STAMP_DIR/.devlog"
touch "$STAMP_DIR/.devlog/.enabled"
printf '## Round 7 — 2026-09-17T09:00:00+0800\n\n### User Input\n```text\ndo X\n```\n\n### Status\nIN_PROGRESS\n' > "$STAMP_DIR/.devlog/devlog.md"
printf '## Round 8 — 2026-09-17T09:30:00+0800\n\n### User Input\n```text\ndo Y\n```\n\n### Status\nIN_PROGRESS\n' > "$STAMP_DIR/.devlog/.round-current.md"
printf '{"round": 8}\n' > "$STAMP_DIR/.devlog/.round-open"
cksum < "$STAMP_DIR/.devlog/.round-current.md" > "$STAMP_DIR/.devlog/.turn-start"

bash "$SCRIPT_DIR/close-open-round.sh" "test_reason"

assert_file_absent "stamp: .round-current.md removed after merge" "$STAMP_DIR/.devlog/.round-current.md"
MAIN_AFTER="$(cat "$STAMP_DIR/.devlog/devlog.md")"
assert_contains "stamp: round 7 (prior history) still present" "## Round 7" "$MAIN_AFTER"
assert_contains "stamp: round 8 merged into devlog.md" "## Round 8" "$MAIN_AFTER"
assert_contains "stamp: INTERRUPTED status merged in" "INTERRUPTED" "$MAIN_AFTER"
assert_contains "stamp: reason tag merged in" "[reason: test_reason]" "$MAIN_AFTER"
rm -rf "$STAMP_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

# --- 8: recovered case also merges (Claude finished before the signal) -----
REC_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$REC_DIR"
mkdir -p "$REC_DIR/.devlog"
touch "$REC_DIR/.devlog/.enabled"
: > "$REC_DIR/.devlog/devlog.md"
printf '## Round 1 — 2026-09-17T09:00:00+0800\n\n### User Input\n```text\ndo X\n```\n\n### Summary\n完成了\n\n### Handoff\n#### 現況\n收尾\n\n### Status\nDONE\n' > "$REC_DIR/.devlog/.round-current.md"
printf '{"round": 1}\n' > "$REC_DIR/.devlog/.round-open"
echo "stale-hash-that-does-not-match" > "$REC_DIR/.devlog/.turn-start"

bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt"

assert_file_absent "recovered: .round-current.md removed after merge" "$REC_DIR/.devlog/.round-current.md"
MAIN_AFTER="$(cat "$REC_DIR/.devlog/devlog.md")"
assert_contains "recovered: finished round merged into devlog.md" "完成了" "$MAIN_AFTER"
assert_not_contains "recovered: no INTERRUPTED stamped over real content" "INTERRUPTED" "$MAIN_AFTER"
if [ -f "$REC_DIR/.devlog/.round-open" ]; then
  echo "FAIL: recovered case should still delete .round-open"
  FAIL=1
else
  echo "PASS: recovered case deleted .round-open"
fi
rm -rf "$REC_DIR"
export CLAUDE_PROJECT_DIR="$TMP_ROOT"

# --- L1: run as a child of the lock holder (round-start.sh's dangling heal)
#         -> no wait on the parent's lock, still stamps, and its EXIT-trap
#         release leaves the parent's lock in place ----------------------
# shellcheck source=../devlog-lock.sh
. "$SCRIPT_DIR/devlog-lock.sh"
write_skeleton
devlog_lock_acquire
START="$(date +%s)"
bash "$SCRIPT_DIR/close-open-round.sh" "dangling:next_prompt"
ELAPSED=$(( $(date +%s) - START ))
if [ "$ELAPSED" -le 1 ]; then
  echo "PASS: child of lock holder doesn't wait (${ELAPSED}s)"
else
  echo "FAIL: child of lock holder waited ${ELAPSED}s"
  FAIL=1
fi
assert_contains "child of lock holder still stamps" $'### Status\nINTERRUPTED' "$(cat "$DEVLOG_DIR/devlog.md")"
if [ -d "$DEVLOG_DIR/.lock" ] && [ "$(cat "$DEVLOG_DIR/.lock/pid" 2>/dev/null)" = "$$" ]; then
  echo "PASS: child's exit leaves the holder's lock"
else
  echo "FAIL: holder's lock removed by child"
  FAIL=1
fi
devlog_lock_release
assert_file_absent "holder release removes lock" "$DEVLOG_DIR/.lock/pid"

# --- L2: lock held by an unrelated live process (no inherited owner) ->
#         still waits out the contention timeout, stamps fail-open, and
#         leaves the foreign lock alone --------------------------------------
write_skeleton
sleep 5 &
LIVE_PID=$!
mkdir "$DEVLOG_DIR/.lock"
echo "$LIVE_PID" > "$DEVLOG_DIR/.lock/pid"
START="$(date +%s)"
bash "$SCRIPT_DIR/close-open-round.sh" "dangling:next_prompt"
ELAPSED=$(( $(date +%s) - START ))
if [ "$ELAPSED" -ge 2 ]; then
  echo "PASS: unrelated holder still contends (${ELAPSED}s)"
else
  echo "FAIL: unrelated holder skipped contention (${ELAPSED}s)"
  FAIL=1
fi
assert_contains "contended run still stamps (fail-open)" $'### Status\nINTERRUPTED' "$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$(cat "$DEVLOG_DIR/.lock/pid" 2>/dev/null)" = "$LIVE_PID" ]; then
  echo "PASS: foreign lock left in place"
else
  echo "FAIL: foreign lock touched"
  FAIL=1
fi
kill "$LIVE_PID" 2>/dev/null || true
wait "$LIVE_PID" 2>/dev/null || true
rm -rf "$DEVLOG_DIR/.lock"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
