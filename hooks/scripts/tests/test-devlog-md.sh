#!/usr/bin/env bash
# Self-check for devlog-md.sh's segment-counting and insertion helpers. Run:
#   bash hooks/scripts/test-devlog-md.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $desc (should not contain: $needle)"; FAIL=1 ;;
    *) echo "PASS: $desc" ;;
  esac
}
assert_file_absent() {
  local desc="$1" file="$2"
  if [ ! -f "$file" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (file exists: $file)"
    FAIL=1
  fi
}
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected exit code $expected, got $actual)"
    FAIL=1
  fi
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

### Reply
fixture reply.

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

### Reply
fixture reply.

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

### Reply
fixture reply.

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

### Reply
fixture reply.

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

# --- devlog_insert_before_summary: still matches "### Summary" with a
# trailing space/tab (built via printf, not a literal in the heredoc, since
# editors tend to strip trailing whitespace on save) -----------------------
{
  printf '## Round 1 — 2026-09-09T12:00:00+08:00\n\n'
  printf '### User Input\n```text\nhello\n```\n\n'
  printf '### Summary \n'
  printf 'done\n\n'
  printf '### Handoff\n#### 現況\ndone\n\n'
  printf '### Status\nDONE\n'
} > "$TMP_ROOT/devlog_trailing_ws.md"
printf '### 段落 1 - 09:30（回覆上一輪的問題）\n```text\nmy trailing-ws answer\n```\n\n' > "$TMP_ROOT/segment_ws.txt"
START="$(devlog_list_round_starts "$TMP_ROOT/devlog_trailing_ws.md" | awk '$2==1{print $1}')"
END="$(devlog_block_end "$TMP_ROOT/devlog_trailing_ws.md" "$START")"
RESULT="$(devlog_insert_before_summary "$TMP_ROOT/devlog_trailing_ws.md" "$START" "$END" "$TMP_ROOT/segment_ws.txt")"
assert_contains "inserted segment text present (Summary has trailing space)" "my trailing-ws answer" "$RESULT"
BEFORE_SUMMARY_WS="$(printf '%s\n' "$RESULT" | awk '/my trailing-ws answer/{print NR} /^### Summary[ \t]*$/{print NR; exit}')"
FIRST_LINE_WS="$(printf '%s\n' "$BEFORE_SUMMARY_WS" | head -1)"
SECOND_LINE_WS="$(printf '%s\n' "$BEFORE_SUMMARY_WS" | tail -1)"
if [ "$FIRST_LINE_WS" -lt "$SECOND_LINE_WS" ]; then
  echo "PASS: segment text appears before the trailing-space ### Summary line"
else
  echo "FAIL: segment text did not land before the trailing-space ### Summary line"
  FAIL=1
fi


# --- indented fence must hide ## Round N from list_round_starts ----------
cat > "$TMP_ROOT/indent.md" <<'EOF'
## Round 1 — real

### Status
DONE

    ```text
    ## Round 99 — fake
    ```

## Round 2 — real

### Status
DONE
EOF
OUT="$(devlog_list_round_starts "$TMP_ROOT/indent.md")"
echo "$OUT" | grep -q ' 1$' || { echo "FAIL: missing round 1"; FAIL=1; }
echo "$OUT" | grep -q ' 2$' || { echo "FAIL: missing round 2"; FAIL=1; }
if echo "$OUT" | grep -q '99'; then
  echo "FAIL: fenced round 99 counted"
  FAIL=1
else
  echo "PASS: indented fence hides Round 99"
fi

# --- devlog_strip_kept_index: rebuilding ## Kept 索引 repeatedly must not
# grow the blank-line separator in front of it (regression: the strip used
# to preserve the pre-existing separator blank line while the rebuild step
# in keep-move.sh unconditionally added another one on top of it) ----------
cat > "$TMP_ROOT/kept.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### Status
DONE
EOF
for i in 1 2 3; do
  STRIPPED="$TMP_ROOT/kept-stripped-$i"
  devlog_strip_kept_index "$TMP_ROOT/kept.md" "$STRIPPED"
  {
    cat "$STRIPPED"
    printf '\n## Kept 索引\n'
    printf -- '- devlog.topic-%s.md\n' "$i"
  } > "$TMP_ROOT/kept.md"
done
HEADING_LINE="$(grep -n '^## Kept 索引' "$TMP_ROOT/kept.md" | head -1 | cut -d: -f1)"
PREV_LINE="$(sed -n "$((HEADING_LINE - 1))p" "$TMP_ROOT/kept.md")"
PREV2_LINE="$(sed -n "$((HEADING_LINE - 2))p" "$TMP_ROOT/kept.md")"
if [ -z "$PREV_LINE" ] && [ -n "$PREV2_LINE" ]; then
  echo "PASS: exactly one blank line separates content from ## Kept 索引 after 3 rebuilds"
else
  echo "FAIL: expected exactly one blank line before ## Kept 索引 after 3 rebuilds, got line $((HEADING_LINE - 1))=[$PREV_LINE] line $((HEADING_LINE - 2))=[$PREV2_LINE]"
  FAIL=1
fi

# --- devlog_strip_lessons_index: same blank-line regression check, for
# "## Lessons 索引" (docs/design/lessons-mode.md) -----------------------
cat > "$TMP_ROOT/lessons.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### Status
DONE
EOF
for i in 1 2 3; do
  STRIPPED="$TMP_ROOT/lessons-stripped-$i"
  devlog_strip_lessons_index "$TMP_ROOT/lessons.md" "$STRIPPED"
  {
    cat "$STRIPPED"
    printf '\n## Lessons 索引\n'
    printf -- '- devlog.lessons.topic-%s.md\n' "$i"
  } > "$TMP_ROOT/lessons.md"
done
HEADING_LINE="$(grep -n '^## Lessons 索引' "$TMP_ROOT/lessons.md" | head -1 | cut -d: -f1)"
PREV_LINE="$(sed -n "$((HEADING_LINE - 1))p" "$TMP_ROOT/lessons.md")"
PREV2_LINE="$(sed -n "$((HEADING_LINE - 2))p" "$TMP_ROOT/lessons.md")"
if [ -z "$PREV_LINE" ] && [ -n "$PREV2_LINE" ]; then
  echo "PASS: exactly one blank line separates content from ## Lessons 索引 after 3 rebuilds"
else
  echo "FAIL: expected exactly one blank line before ## Lessons 索引 after 3 rebuilds, got line $((HEADING_LINE - 1))=[$PREV_LINE] line $((HEADING_LINE - 2))=[$PREV2_LINE]"
  FAIL=1
fi

# --- devlog_lessons_index_lines: reads back only the block body ------------
LINES="$(devlog_lessons_index_lines "$TMP_ROOT/lessons.md")"
case "$LINES" in
  *"devlog.lessons.topic-3.md"*) echo "PASS: devlog_lessons_index_lines reads the rebuilt line" ;;
  *) echo "FAIL: expected devlog.lessons.topic-3.md in lines, got: $LINES"; FAIL=1 ;;
esac
case "$LINES" in
  *"## Lessons 索引"*) echo "FAIL: devlog_lessons_index_lines must not include the heading itself"; FAIL=1 ;;
  *) echo "PASS: devlog_lessons_index_lines excludes the heading" ;;
esac

# --- last-round 工作區 body + claim state (no git needed for NO_CLAIM) ----
cat > "$TMP_ROOT/claim.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### Summary
old

### Reply
fixture reply.

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨
#### 現況
still going

### Status
IN_PROGRESS

## Round 2 — 2026-09-11T00:01:00+08:00

### Summary
newer

### Reply
fixture reply.

### Handoff
#### 工作區
feat/foo @ abc1234
未提交：a.txt
#### 現況
x

### Status
BLOCKED
EOF
START="$(devlog_list_round_starts "$TMP_ROOT/claim.md" | awk 'END { print $1 }')"
END="$(devlog_block_end "$TMP_ROOT/claim.md" "$START")"
assert_eq "last round is 2" "2" "$(devlog_list_round_starts "$TMP_ROOT/claim.md" | awk 'END { print $2 }')"
assert_eq "last-round status BLOCKED" "BLOCKED" "$(devlog_round_status "$TMP_ROOT/claim.md" "$START" "$END")"
WS_BODY="$(devlog_round_workspace_body "$TMP_ROOT/claim.md" "$START" "$END")"
EXPECTED_BODY='feat/foo @ abc1234
未提交：a.txt'
assert_eq "workspace body two lines" "$EXPECTED_BODY" "$WS_BODY"

cat > "$TMP_ROOT/segments.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### User Input
main @ user-input-only，工作樹乾淨

### 段落 1
first
```text
main @ live123，工作樹乾淨
```

### Summary
main @ summary-only，工作樹乾淨

### 段落 2
second
EOF
SEG_START="$(devlog_list_round_starts "$TMP_ROOT/segments.md" | awk 'END { print $1 }')"
SEG_END="$(devlog_block_end "$TMP_ROOT/segments.md" "$SEG_START")"
SEG_BODY="$(devlog_round_segments_body "$TMP_ROOT/segments.md" "$SEG_START" "$SEG_END")"
assert_contains "segment bodies include first segment" "first" "$SEG_BODY"
assert_contains "segment bodies include fenced snapshot" "main @ live123，工作樹乾淨" "$SEG_BODY"
assert_contains "segment bodies include second segment" "second" "$SEG_BODY"
case "$SEG_BODY" in
  *user-input-only*|*summary-only*) echo "FAIL: non-segment text leaked"; FAIL=1 ;;
  *) echo "PASS: non-segment text excluded" ;;
esac

cat > "$TMP_ROOT/done.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨

### Status
DONE
EOF
assert_eq "DONE is NO_CLAIM" "NO_CLAIM" "$(workspace_claim_state "$TMP_ROOT" "$TMP_ROOT/done.md")"

cat > "$TMP_ROOT/empty-ws.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### Handoff
#### 現況
x

### Status
IN_PROGRESS
EOF
assert_eq "missing 工作區 is NO_CLAIM" "NO_CLAIM" "$(workspace_claim_state "$TMP_ROOT" "$TMP_ROOT/empty-ws.md")"

cat > "$TMP_ROOT/interrupted.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨

### Status
INTERRUPTED
[reason: dangling:next_prompt]
EOF
assert_eq "INTERRUPTED+reason with 工作區 is not DONE" "MISMATCH" "$(workspace_claim_state "$TMP_ROOT" "$TMP_ROOT/interrupted.md")"

# --- fence parity bug: an unclosed ``` earlier in the round (e.g. pasted
# code in User Input that forgot to close its fence) must not make the
# real #### 工作區 further down invisible. enforce-devlog.sh guards this
# exact class of bug with NOFENCE fail-open; devlog-md.sh's range-scoped
# functions (used by workspace_claim_state / round-start.sh /
# segment-watch.sh) must degrade the same way, not silently return empty. --
cat > "$TMP_ROOT/unclosed-fence.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### User Input
```text
使用者貼了一段忘記收尾的程式碼
def foo():
    pass

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨
#### 現況
測試 fence parity bug

### Status
IN_PROGRESS
EOF
START="$(devlog_list_round_starts "$TMP_ROOT/unclosed-fence.md" | awk 'END { print $1 }')"
END="$(devlog_block_end "$TMP_ROOT/unclosed-fence.md" "$START")"
assert_eq "status survives unclosed fence" "IN_PROGRESS" "$(devlog_round_status "$TMP_ROOT/unclosed-fence.md" "$START" "$END")"
assert_eq "workspace body survives unclosed fence" "main @ deadbeef，工作樹乾淨" "$(devlog_round_workspace_body "$TMP_ROOT/unclosed-fence.md" "$START" "$END")"
# workspace_claim_state on a non-git dir: workspace_snapshot returns "非 git
# 工作區", which differs from the claimed body above -> must be MISMATCH.
# Before the fix this came back NO_CLAIM because the claimed body parsed
# empty, silently defeating the whole drift-detection feature.
NONGIT_DIR="$TMP_ROOT/nongit"
mkdir -p "$NONGIT_DIR"
assert_eq "unclosed fence still yields a claim (MISMATCH, not NO_CLAIM)" "MISMATCH" "$(workspace_claim_state "$NONGIT_DIR" "$TMP_ROOT/unclosed-fence.md")"

cat > "$TMP_ROOT/unclosed-fence-segments.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### User Input
```text
使用者貼了一段忘記收尾的程式碼
def foo():
    pass

### 段落 1
real segment content

### Status
IN_PROGRESS
EOF
SEG_START="$(devlog_list_round_starts "$TMP_ROOT/unclosed-fence-segments.md" | awk 'END { print $1 }')"
SEG_END="$(devlog_block_end "$TMP_ROOT/unclosed-fence-segments.md" "$SEG_START")"
assert_contains "segment body survives unclosed fence" "real segment content" "$(devlog_round_segments_body "$TMP_ROOT/unclosed-fence-segments.md" "$SEG_START" "$SEG_END")"

# --- devlog_merge_round_current ---------------------------------------
mkdir -p "$TMP_ROOT/.devlog"
MERGE_MAIN="$TMP_ROOT/.devlog/merge-main.md"
MERGE_CUR="$TMP_ROOT/.devlog/merge-current.md"

printf '## Round 1 — 2026-09-17T09:00:00+0800\n\n### Summary\ndone\n\n### Handoff\n#### 現況\nok\n\n### Status\nDONE\n' > "$MERGE_MAIN"
printf '## Round 2 — 2026-09-17T09:05:00+0800\n\n### User Input\n```text\nhi\n```\n\n### Summary\ns2\n\n### Handoff\n#### 現況\nc2\n\n### Status\nDONE\n' > "$MERGE_CUR"

devlog_merge_round_current "$MERGE_MAIN" "$MERGE_CUR"

MERGED="$(cat "$MERGE_MAIN")"
assert_contains "merge: round 1 still present" "## Round 1" "$MERGED"
assert_contains "merge: round 2 appended" "## Round 2" "$MERGED"
assert_file_absent "merge: round-current removed after merge" "$MERGE_CUR"

# merging an absent/empty round-current is a silent no-op
BEFORE="$(cat "$MERGE_MAIN")"
devlog_merge_round_current "$MERGE_MAIN" "$MERGE_CUR"
AFTER="$(cat "$MERGE_MAIN")"
if [ "$BEFORE" = "$AFTER" ]; then echo "PASS: merge no-op when round-current absent"; else echo "FAIL: merge no-op when round-current absent"; FAIL=1; fi

# --- devlog_reopen_last_round ------------------------------------------
REOPEN_MAIN="$TMP_ROOT/.devlog/reopen-main.md"
REOPEN_CUR="$TMP_ROOT/.devlog/reopen-current.md"
rm -f "$REOPEN_CUR"

printf '## Round 1 — 2026-09-17T09:00:00+0800\n\n### Summary\ns1\n\n### Handoff\n#### 現況\nc1\n\n### Status\nDONE\n\n## Round 2 — 2026-09-17T09:10:00+0800\n\n### User Input\n```text\n問題？\n```\n\n### Summary\ns2\n\n### Handoff\n#### 現況\nBLOCKED 等答案\n\n### Status\nBLOCKED\n' > "$REOPEN_MAIN"

devlog_reopen_last_round "$REOPEN_MAIN" "$REOPEN_CUR"
RC=$?
assert_exit "reopen: returns 0 when a round exists" 0 "$RC"

REOPENED="$(cat "$REOPEN_CUR" 2>/dev/null || echo '')"
assert_contains "reopen: round 2 moved into round-current" "## Round 2" "$REOPENED"
assert_not_contains "reopen: round 1 not pulled along" "## Round 1" "$REOPENED"

REMAINING="$(cat "$REOPEN_MAIN")"
assert_contains "reopen: round 1 stays in main file" "## Round 1" "$REMAINING"
assert_not_contains "reopen: round 2 removed from main file" "## Round 2" "$REMAINING"

# reopen on a file with no round at all fails without touching either file
EMPTY_MAIN="$TMP_ROOT/.devlog/empty-main.md"
: > "$EMPTY_MAIN"
rm -f "$TMP_ROOT/.devlog/should-not-exist.md"
devlog_reopen_last_round "$EMPTY_MAIN" "$TMP_ROOT/.devlog/should-not-exist.md"
assert_exit "reopen: returns 1 when no round exists" 1 $?
assert_file_absent "reopen: no round-current created on failure" "$TMP_ROOT/.devlog/should-not-exist.md"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
