# Hook Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the recording-moments hooks so forked sessions actually run SessionStart, Stop tells Claude to edit the last Round instead of appending a new one, and `close-open-round.sh` does not stamp `INTERRUPTED` on a Round that already closed.

**Architecture:** Three independent follow-ups on the already-shipped recording-moments loop. Task 1 is a `hooks.json` matcher plus docs. Task 2 is two stderr strings and the tests that read them. Task 3 moves the recovered-complete rule into `close-open-round.sh` (hash moved vs `.turn-start` **and** last Round has `### Summary` + `### Handoff`) so SessionEnd, next-prompt heal, and SessionStart share it; `enforce-devlog.sh` drops its private copy of that awk.

**Tech Stack:** bash hooks, `cksum`, fence-aware awk already in `close-open-round.sh` / `enforce-devlog.sh`; assert-and-exit self-checks (`bash hooks/scripts/test-*.sh`).

## Global Constraints

- Spec baseline: `docs/design/recording-moments.md` on `feat/jinze/improve_response_content` as of 2026-09-09 (HEAD `bfe2151`).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- Completeness remains presence-only `### Summary` + `### Handoff`. Do not add body quality checks.
- Fail-open unchanged: missing `.enabled` → no-op; helper always `exit 0`.
- `close-open-round.sh` must stay **silent on stdout**. SessionStart injects its stdout as additionalContext; a `stamped`/`released` print would leak into Claude's context.
- Recovered-complete (do not stamp) if and only if: `.round-open` matches the last fence-aware `## Round` number, that block has both `### Summary` and `### Handoff`, `.turn-start` exists, both hashes are readable, and `cksum < devlog.md` differs from `.turn-start`. Use the same `cksum < file` form as `enforce-devlog.sh` (no `tr -d '\n'`).
- If `.turn-start` is missing, unreadable, or the hash is unchanged: still stamp (preserves `test-close-open-round.sh` case 3 — headings + `IN_PROGRESS` + no hash proof).
- Hash-miss stderr must still contain the exact substring `User Input / Summary / Handoff / Status` (existing Heading Scenario 1). It must also contain `編輯最後一個 Round` and `不要再新增一個 ## Round`.
- Heading-miss stderr must still mention `### Summary` and `### Handoff`. It must also contain `不要再新增一個 ## Round`.
- SessionStart matcher becomes exactly `startup|resume|clear|compact|fork`.
- Do not bump `.claude-plugin/plugin.json` version.
- Do not parse `transcript_path`. Do not add PostToolUse / Subagent / PreCompact hooks.
- Do not change `segment-watch.sh`.
- Interrupt stub strings stay exact: Summary `這輪意外中斷。`; Handoff `#### 現況` then `這輪沒有正常收尾。`

## File Structure

| File | Responsibility |
|---|---|
| `hooks/hooks.json` | SessionStart matcher includes `fork` |
| `hooks/scripts/test-session-start-devlog.sh` | Matcher assertion + `source=fork` heal + completed-round skip-heal |
| `skills/devlog-tracker/SKILL.md` | Matcher / description mention `fork` |
| `README.md` | 自動接續 mentions fork |
| `docs/design/recording-moments.md` | Known-limitation SessionStart list includes `fork`; helper documents recovered-complete |
| `hooks/scripts/test-enforce-devlog.sh` | Hash-miss / heading-miss copy assertions |
| `hooks/scripts/enforce-devlog.sh` | New stderr; `.interrupted` calls helper only |
| `hooks/scripts/test-close-open-round.sh` | Recovered-complete + hash-equal-still-stamps |
| `hooks/scripts/close-open-round.sh` | Recovered-complete before patch; awk exit 3 |
| `hooks/scripts/test-on-interrupt.sh` | SessionEnd on a completed open Round |
| `hooks/scripts/test-round-start.sh` | Next prompt does not interrupt a completed last Round |

---

### Task 1: SessionStart matcher includes `fork`

**Files:**
- Modify: `hooks/hooks.json` (SessionStart `matcher` only)
- Modify: `hooks/scripts/test-session-start-devlog.sh` (append before the final `FAIL` summary)
- Modify: `skills/devlog-tracker/SKILL.md` (YAML `description` + 自動接續 paragraph)
- Modify: `README.md` (自動接續 bullet)
- Modify: `docs/design/recording-moments.md` (known-limitation SessionStart list)
- Test: `bash hooks/scripts/test-session-start-devlog.sh`

**Interfaces:**
- Consumes: `session-start-devlog.sh` already heals when stdin `source` is `startup|resume|clear|fork`.
- Produces: Claude Code actually invokes that script on `fork`; tests fail if the matcher string drops `fork`.

- [ ] **Step 1: Write the failing self-check**

In `hooks/scripts/test-session-start-devlog.sh`, immediately before the final `if [ "$FAIL" -eq 0 ]; then` block, insert:

```bash
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
```

- [ ] **Step 2: Run it to verify Scenario 7 fails**

Run: `bash hooks/scripts/test-session-start-devlog.sh`

Expected: `FAIL: SessionStart matcher must be exactly startup|resume|clear|compact|fork`. Scenario 8 may already PASS (the script already treats `fork` as a heal source). Overall exit 1.

- [ ] **Step 3: Wire the matcher and docs**

In `hooks/hooks.json`, change only the SessionStart matcher:

```json
        "matcher": "startup|resume|clear|compact|fork",
```

In `skills/devlog-tracker/SKILL.md` YAML `description`, replace `startup / resume / clear / compact` with `startup / resume / clear / compact / fork`.

In the 自動接續 paragraph, replace this sentence:

```
matcher 設為 `startup|resume|clear|compact`，也就是**開新 session、resume、使用者按 `/clear`，或 `/compact` 壓縮對話之後**都會自動觸發：
```

with:

```
matcher 設為 `startup|resume|clear|compact|fork`，也就是**開新 session、resume、使用者按 `/clear`、`/compact` 壓縮對話之後，或 `/fork`／`--fork-session` 分支出去的 session**都會自動觸發：
```

In `README.md`, replace the 自動接續 bullet:

```
- **自動接續**：`SessionStart` hook，`/clear`、resume、開新 session 時自動讀取
  `.devlog/devlog.md` 最後幾輪並注入 context，不用手動喊指令。
```

with:

```
- **自動接續**：`SessionStart` hook，`/clear`、resume、開新 session、`/fork` 時自動讀取
  `.devlog/devlog.md` 最後幾輪並注入 context，不用手動喊指令。
```

In `docs/design/recording-moments.md` Known limitations, replace both `startup` / `resume` / `clear` lists that describe SessionStart heal so they also name `fork`. The Hard kill bullet and the Esc bullet each say:

```
SessionStart (`startup` / `resume` / `clear`)
```

Change each to:

```
SessionStart (`startup` / `resume` / `clear` / `fork`)
```

Do not change the compact-skip-heal bullet.

- [ ] **Step 4: Run the self-check**

Run: `bash hooks/scripts/test-session-start-devlog.sh`

Expected: `All checks passed.` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json hooks/scripts/test-session-start-devlog.sh skills/devlog-tracker/SKILL.md README.md docs/design/recording-moments.md
git commit -m "$(cat <<'EOF'
Include fork in the SessionStart matcher so branched sessions heal.

EOF
)"
```

---

### Task 2: Stop block messages say edit the last Round

**Files:**
- Modify: `hooks/scripts/test-enforce-devlog.sh` (Heading Scenario 1 and Heading Scenario 3 `case` blocks)
- Modify: `hooks/scripts/enforce-devlog.sh` (the hash-miss `echo` and the heading-miss `echo`)
- Test: `bash hooks/scripts/test-enforce-devlog.sh`

**Interfaces:**
- Consumes: existing hash-miss / heading-miss `exit 2` paths.
- Produces: stderr that still names the required headings, and tells Claude to edit the last Round instead of appending `## Round`.

- [ ] **Step 1: Extend the failing copy assertions**

In `hooks/scripts/test-enforce-devlog.sh` Heading Scenario 1, immediately after the existing `User Input / Response / Status` `case` block, append:

```bash
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
```

In Heading Scenario 3, immediately after the existing `### Summary` / `### Handoff` `case` block, append:

```bash
case "$HEADING_MISS_MSG" in
  *"不要再新增一個 ## Round"*) echo "PASS: heading-miss message forbids a second Round" ;;
  *) echo "FAIL: heading-miss message should say 不要再新增一個 ## Round, got: $HEADING_MISS_MSG"; FAIL=1 ;;
esac
```

- [ ] **Step 2: Run to verify the new cases fail**

Run: `bash hooks/scripts/test-enforce-devlog.sh`

Expected: FAIL on `hash-miss message should say 編輯最後一個 Round` and/or `hash-miss message still tells Claude to append a Round`. Existing heading scenarios other than the new `case` lines stay green.

- [ ] **Step 3: Replace the two stderr strings**

In `hooks/scripts/enforce-devlog.sh`, replace the hash-miss `echo` with exactly:

```bash
  echo "這一輪的 Round 只有 hook 寫的 User Input skeleton，還沒有收尾。請依 skills/devlog-tracker/SKILL.md 編輯最後一個 Round，補上 User Input / Summary / Handoff / Status。不要再新增一個 ## Round。" >&2
```

Replace the heading-miss `echo` with exactly:

```bash
    echo "最後一個 Round 缺少 \`### Summary\` 或 \`### Handoff\`。請依 skills/devlog-tracker/SKILL.md 補上這兩個標題（Summary 給人掃、Handoff 給下一輪接續），寫在同一個 Round 裡，不要再新增一個 ## Round。" >&2
```

Do not change exit codes or any other branch.

- [ ] **Step 4: Run**

Run: `bash hooks/scripts/test-enforce-devlog.sh`

Expected: `All checks passed.` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/enforce-devlog.sh hooks/scripts/test-enforce-devlog.sh
git commit -m "$(cat <<'EOF'
Tell Claude to edit the last Round when Stop blocks, not append another.

EOF
)"
```

---

### Task 3: Recovered-complete lives in `close-open-round.sh`

**Files:**
- Modify: `hooks/scripts/test-close-open-round.sh` (append before the final `FAIL` summary)
- Modify: `hooks/scripts/close-open-round.sh`
- Modify: `hooks/scripts/enforce-devlog.sh` (replace the recovered-complete awk with a helper call)
- Modify: `hooks/scripts/test-on-interrupt.sh` (SessionEnd completed-round case)
- Modify: `hooks/scripts/test-round-start.sh` (dangling heal on a completed last Round)
- Modify: `hooks/scripts/test-session-start-devlog.sh` (startup heal on a completed last Round)
- Modify: `docs/design/recording-moments.md` (Shared helper + Stop `.interrupted` bullets)
- Test: the six `test-*.sh` scripts listed in Step 4

**Interfaces:**
- Consumes: `$1` reason string; `CLAUDE_PROJECT_DIR`; `.enabled`; `.round-open`; `.turn-start`; `devlog.md`.
- Produces: always `exit 0`, no stdout. On recovered-complete: file unchanged, markers deleted, awk exit 3 (caller does not `mv` the tmp). On incomplete / no hash proof: same stamp as today. `enforce-devlog.sh` calls the helper when `.interrupted` exists; if the last Round then contains `INTERRUPTED` plus the reason `user_interrupt`, it `exit 0`; otherwise it falls through (recovered or stale flag).

- [ ] **Step 1: Write the failing helper cases**

In `hooks/scripts/test-close-open-round.sh`, immediately before the final `if [ "$FAIL" -eq 0 ]; then` block, insert:

```bash
# --- 7: completed last Round + hash moved -> do not stamp -----------------
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
touch "$DEVLOG_DIR/.interrupted"
BEFORE="$(cat "$DEVLOG_DIR/devlog.md")"
bash "$SCRIPT_DIR/close-open-round.sh" "SessionEnd:clear"
AFTER="$(cat "$DEVLOG_DIR/devlog.md")"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: recovered-complete -> devlog.md unchanged"
else
  echo "FAIL: recovered-complete edited a finished Round"
  FAIL=1
fi
assert_not_contains "recovered-complete must not stamp" "INTERRUPTED" "$AFTER"
assert_contains "recovered-complete keeps DONE" $'### Status\nDONE' "$AFTER"
if [ -f "$DEVLOG_DIR/.round-open" ] || [ -f "$DEVLOG_DIR/.interrupted" ]; then
  echo "FAIL: recovered-complete should still delete markers"
  FAIL=1
else
  echo "PASS: recovered-complete deleted markers"
fi

# --- 8: headings present but hash equal -> still stamp (no recovery proof)
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
cksum < "$DEVLOG_DIR/devlog.md" > "$DEVLOG_DIR/.turn-start"
bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
assert_contains "hash-equal headings still stamp" "INTERRUPTED" "$BODY"
assert_contains "hash-equal reason" "user_interrupt" "$BODY"
```

In `hooks/scripts/test-on-interrupt.sh`, immediately before the final `if [ "$FAIL" -eq 0 ]; then` block, insert:

```bash
# SessionEnd on a completed open Round must not stamp
write_open
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
echo '{"reason":"clear"}' | bash "$SCRIPT_DIR/on-session-end.sh"
BODY="$(cat "$DEVLOG_DIR/devlog.md")"
case "$BODY" in
  *INTERRUPTED*) echo "FAIL: SessionEnd must not stamp a completed Round"; FAIL=1 ;;
  *) echo "PASS: SessionEnd left completed Status DONE" ;;
esac
if [ -f "$DEVLOG_DIR/.round-open" ]; then
  echo "FAIL: SessionEnd recovered-complete should delete .round-open"
  FAIL=1
else
  echo "PASS: SessionEnd recovered-complete deleted .round-open"
fi
```

In `hooks/scripts/test-round-start.sh`, immediately before the final `if [ "$FAIL" -eq 0 ]; then` block, insert:

```bash
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
```

In `hooks/scripts/test-session-start-devlog.sh`, immediately before the final `if [ "$FAIL" -eq 0 ]; then` block (after the Task 1 scenarios if they are already in the file), insert:

```bash
# --- Scenario 9: startup does not interrupt a completed last Round ---------
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
```

- [ ] **Step 2: Run to verify the new cases fail**

Run:

```bash
bash hooks/scripts/test-close-open-round.sh
```

Expected: `FAIL: recovered-complete edited a finished Round` (current helper always stamps when the round number matches).

- [ ] **Step 3: Patch `close-open-round.sh`**

Replace `hooks/scripts/close-open-round.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Stamp the open Round as INTERRUPTED. Always exit 0 (fail-open).
# Usage: close-open-round.sh <reason>
# Silent on stdout — SessionStart injects stdout as additionalContext.
set -uo pipefail

REASON="${1:-unknown}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DEVLOG_DIR="$PROJECT_DIR/.devlog"
ENABLED_FLAG="$DEVLOG_DIR/.enabled"
ROUND_OPEN="$DEVLOG_DIR/.round-open"
INTERRUPTED_FLAG="$DEVLOG_DIR/.interrupted"
DEVLOG_FILE="$DEVLOG_DIR/devlog.md"
TURN_MARKER="$DEVLOG_DIR/.turn-start"

drop_markers() {
  rm -f "$ROUND_OPEN" "$INTERRUPTED_FLAG" 2>/dev/null || true
}

[ -f "$ENABLED_FLAG" ] || exit 0
if [ ! -f "$ROUND_OPEN" ]; then
  rm -f "$INTERRUPTED_FLAG" 2>/dev/null || true
  exit 0
fi

OPEN_ROUND="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$ROUND_OPEN" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
case "$OPEN_ROUND" in
  ''|*[!0-9]*) drop_markers; exit 0 ;;
esac

if [ ! -f "$DEVLOG_FILE" ]; then
  drop_markers
  exit 0
fi

RECOVERED=0
if [ -f "$TURN_MARKER" ]; then
  TURN_HASH="$(cat "$TURN_MARKER" 2>/dev/null || echo '')"
  CUR_HASH="$(cksum < "$DEVLOG_FILE" 2>/dev/null || echo '')"
  if [ -n "$TURN_HASH" ] && [ -n "$CUR_HASH" ] && [ "$CUR_HASH" != "$TURN_HASH" ]; then
    RECOVERED=1
  fi
fi

TMP="$DEVLOG_FILE.tmp"
awk -v want="$OPEN_ROUND" -v reason="$REASON" -v recovered="$RECOVERED" '
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
    if (recovered && has_s && has_h) { exit 3 }

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

Then replace the `.interrupted` block in `hooks/scripts/enforce-devlog.sh` (from `if [ -f "$DEVLOG_DIR/.interrupted" ]; then` through the closing `fi` before the `jq` loop-guard parse) with:

```bash
if [ -f "$DEVLOG_DIR/.interrupted" ]; then
  bash "$SCRIPT_DIR/close-open-round.sh" "user_interrupt" || true
  # Helper is silent. If it stamped, the last Round now has
  # INTERRUPTED + user_interrupt — exit 0 so Esc is not converted
  # into "please write Summary". Recovered-complete or a stale flag
  # leaves Status alone; fall through to hash / headings / checkpoint.
  _LAST_ROUND="$(awk '
    /^[ \t]*```/ { fence = !fence }
    !fence && /^## Round / { start = NR }
    { lines[NR] = $0; infence[NR] = fence }
    END {
      if (start == 0) exit 0
      end = NR
      for (i = start + 1; i <= NR; i++) {
        if (!infence[i] && lines[i] ~ /^## /) { end = i - 1; break }
      }
      for (i = start; i <= end; i++) print lines[i]
    }
  ' "$DEVLOG_FILE" 2>/dev/null || true)"
  case "$_LAST_ROUND" in
    *$'\nINTERRUPTED\nuser_interrupt'*) exit 0 ;;
  esac
fi
```

Keep `DEVLOG_FILE` / `TURN_MARKER` / `PROJECT_DIR` / `DEVLOG_DIR` assignments that already sit above this block. Do not reintroduce the recovered-complete hash/heading awk that this block used to own.

- [ ] **Step 4: Update the recording-moments helper spec**

In `docs/design/recording-moments.md` Shared helper, after the mismatch fail-open bullet, insert:

```
- If the last Round already has `### Summary` and `### Handoff` **and**
  `devlog.md`'s `cksum` differs from `.turn-start`, delete the markers
  and do not edit Status (recovered-complete). Missing or equal
  `.turn-start` still stamps.
```

In the Stop `.interrupted` bullet, keep the recovered-complete product rule, and note it is now implemented inside `close-open-round.sh` so SessionEnd / next prompt / SessionStart share it.

- [ ] **Step 5: Run the suite**

```bash
bash hooks/scripts/test-close-open-round.sh
bash hooks/scripts/test-on-interrupt.sh
bash hooks/scripts/test-round-start.sh
bash hooks/scripts/test-session-start-devlog.sh
bash hooks/scripts/test-enforce-devlog.sh
bash hooks/scripts/test-segment-watch.sh
```

Expected: all six print `All checks passed.`

`test-close-open-round.sh` case 3 (headings, no `.turn-start`) must still stamp. Case 8 (headings, hash equal) must still stamp. The existing `test-enforce-devlog.sh` recovered-complete + `.interrupted` scenario must still keep Status `DONE`.

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/close-open-round.sh hooks/scripts/test-close-open-round.sh hooks/scripts/enforce-devlog.sh hooks/scripts/test-on-interrupt.sh hooks/scripts/test-round-start.sh hooks/scripts/test-session-start-devlog.sh docs/design/recording-moments.md
git commit -m "$(cat <<'EOF'
Skip INTERRUPTED when the open Round already has a completed close.

EOF
)"
```

---

## Spec coverage (self-review)

| Requirement | Task |
|---|---|
| SessionStart matcher `startup\|resume\|clear\|compact\|fork` | 1 |
| SKILL / README / known-limitation `fork` wording | 1 |
| `source=fork` still heals a skeleton | 1 (Scenario 8) |
| Hash-miss stderr: edit last Round, keep `User Input / Summary / Handoff / Status`, no append | 2 |
| Heading-miss stderr: same Round, no append | 2 |
| Helper recovered-complete when headings + hash moved | 3 |
| Helper still stamps when hash equal or `.turn-start` missing | 3 (case 3 + new case 8) |
| Helper silent on stdout | 3 (constraint + no `echo`) |
| SessionEnd / next prompt / SessionStart share the skip | 3 |
| Stop `.interrupted` still exits 0 on a real stamp, falls through on recover / stale flag | 3 |
| Existing interrupt stubs / usage skip / compact skip-heal unchanged | (no task) |

## Placeholder scan

No TBD / later / "add tests" without code. Helper, stderr strings, matcher, and every new self-check block are written out in full.

## Type consistency

- Heal reason strings unchanged: `dangling:session_start`, `dangling:next_prompt`, `user_interrupt`, `SessionEnd:<reason>`, `StopFailure:<error>`.
- Marker files unchanged: `.round-open`, `.interrupted`, `.turn-start`.
- Awk recovered signal is exit 3 (not used by other scripts; only `close-open-round.sh` reads `AWK_RC`).
