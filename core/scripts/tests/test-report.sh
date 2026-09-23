#!/usr/bin/env bash
# Self-check for report-devlog.sh (docs/design/read-side-and-promote.md B).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
FAIL=0
assert_line() {
  local desc="$1" expected="$2" out="$3"
  if printf '%s\n' "$out" | grep -qxF "$expected"; then echo "PASS: $desc"
  else echo "FAIL: $desc (missing line [$expected] in: $out)"; FAIL=1; fi
}
assert_no_line_prefix() {
  local desc="$1" prefix="$2" out="$3"
  if printf '%s\n' "$out" | grep -q "^$prefix"; then echo "FAIL: $desc (found $prefix)"; FAIL=1
  else echo "PASS: $desc"; fi
}
jcheck() {
  local desc="$1" json="$2" expr="$3"
  if ! command -v node >/dev/null 2>&1; then echo "SKIP: $desc (no node)"; return 0; fi
  if printf '%s' "$json" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8')); process.exit(($expr)?0:1)"; then
    echo "PASS: $desc"
  else echo "FAIL: $desc"; FAIL=1; fi
}

# --- No .devlog -> NOT_STARTED ----------------------------------------------
OUT="$(bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "no .devlog -> NOT_STARTED" "NOT_STARTED" "$OUT"

# --- Fixture ------------------------------------------------------------------
mkdir -p "$DEVLOG_DIR"
{
  cat <<'EOF'
## Round 1 — 2026-09-01T10:00:00+0800

### User Input
secret-input-text

### Summary
EOF
  printf 'first "quoted" \\ back\ttab 中文\n'
  cat <<'EOF'

### Handoff
#### 現況
x

### Status
DONE

## Round 2 — 2026-09-02T10:00:00+0800

### Summary
blocked one
```
## Round 9 fake inside fence
```

### Status
BLOCKED

## Checkpoint（Round 1-2）
### 決策
- keep it

## Round 3 — 2026-09-03T10:00:00+0800

### Summary
in progress

### 段落 探索
seg body

### Status
INTERRUPTED
[reason: dangling:next_prompt]

## Kept 索引
- `devlog.topic-a.md`：Round 5-5，kept_at 2026-09-05T00:00:00+0800，topic a
EOF
} > "$DEVLOG_DIR/devlog.md"
cat > "$DEVLOG_DIR/devlog.archive.md" <<'EOF'
## Round 0 — 2026-08-31T10:00:00+0800

### Summary
archived

### Status
DONE
EOF
cat > "$DEVLOG_DIR/devlog.topic-a.md" <<'EOF'
## Round 5 — 2026-09-05T10:00:00+0800

### Summary
kept topic

### Status
DONE
EOF
cat > "$DEVLOG_DIR/devlog.feat-x.md" <<'EOF'
## Round 1 — 2026-09-04T10:00:00+0800

### Summary
branch work

### Status
IN_PROGRESS
EOF
printf '# Lessons: foo\n\n## 2026-09-01T00:00:00+0800\nlesson.\n' > "$DEVLOG_DIR/devlog.lessons.foo.md"

# --- Default KEY=VALUE --------------------------------------------------------
OUT="$(bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "branch" "BRANCH=main" "$OUT"
assert_line "total rounds = archive + main, fenced fake ignored" "ROUNDS_TOTAL=4" "$OUT"
assert_line "main rounds" "ROUNDS_MAIN=3" "$OUT"
assert_line "archive rounds" "ROUNDS_ARCHIVE=1" "$OUT"
assert_line "done count" "STATUS_DONE=2" "$OUT"
assert_line "in-progress count (branch file not scanned)" "STATUS_IN_PROGRESS=0" "$OUT"
assert_line "blocked count" "STATUS_BLOCKED=1" "$OUT"
assert_line "interrupted count despite reason line" "STATUS_INTERRUPTED=1" "$OUT"
assert_line "blocked ratio" "BLOCKED_RATIO=25" "$OUT"
assert_line "checkpoints" "CHECKPOINTS=1" "$OUT"
assert_line "kept topics" "KEPT_TOPICS=1" "$OUT"
assert_line "lessons topics" "LESSONS_TOPICS=1" "$OUT"
assert_line "first round at" "FIRST_ROUND_AT=2026-08-31T10:00:00+0800" "$OUT"
assert_line "last round at" "LAST_ROUND_AT=2026-09-03T10:00:00+0800" "$OUT"
assert_no_line_prefix "no advisory state -> no LESSONS_ADVISORY" "LESSONS_ADVISORY=" "$OUT"

printf '%s\n' '{"count": 2, "threshold": 3}' > "$DEVLOG_DIR/.lessons-advisory-state"
OUT="$(bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "advisory state present" "LESSONS_ADVISORY=2/3" "$OUT"
rm -f "$DEVLOG_DIR/.lessons-advisory-state"

# --- Empty devlog dir: zeros and none ----------------------------------------
EMPTY_ROOT="$(mktemp -d)"
mkdir -p "$EMPTY_ROOT/.devlog"
OUT="$(CLAUDE_PROJECT_DIR="$EMPTY_ROOT" bash "$SCRIPT_DIR/report-devlog.sh")"
assert_line "empty: zero rounds" "ROUNDS_TOTAL=0" "$OUT"
assert_line "empty: zero ratio" "BLOCKED_RATIO=0" "$OUT"
assert_line "empty: first none" "FIRST_ROUND_AT=none" "$OUT"
rm -rf "$EMPTY_ROOT"

# --- Unknown arg -> exit 2 ------------------------------------------------------
bash "$SCRIPT_DIR/report-devlog.sh" --bogus >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 2 ]; then echo "PASS: unknown arg exits 2"; else echo "FAIL: unknown arg exit $RC"; FAIL=1; fi

# --- --json (no rounds) -------------------------------------------------------
J="$(bash "$SCRIPT_DIR/report-devlog.sh" --json)"
jcheck "json: started + counts are numbers" "$J" 'd.started===true && d.rounds_total===4 && d.status_blocked===1 && d.blocked_ratio===25'
jcheck "json: branch + times" "$J" 'd.branch==="main" && d.first_round_at==="2026-08-31T10:00:00+0800"'
jcheck "json: no advisory -> null" "$J" 'd.lessons_advisory===null'
jcheck "json: no rounds array without --rounds" "$J" '!("rounds" in d) && !("checkpoint_blocks" in d)'

# --- --json --rounds ------------------------------------------------------------
J="$(bash "$SCRIPT_DIR/report-devlog.sh" --json --rounds)"
jcheck "rounds: 4 entries, archive first" "$J" 'd.rounds.length===4 && d.rounds[0].branch==="archive" && d.rounds[0].n===0'
jcheck "rounds: escaping survives quote/backslash/tab/CJK" "$J" 'd.rounds[1].summary.includes("\"quoted\"") && d.rounds[1].summary.includes("\\") && d.rounds[1].summary.includes("\t") && d.rounds[1].summary.includes("中文")'
jcheck "rounds: fenced fake heading stays inside summary" "$J" 'd.rounds[2].summary.includes("## Round 9 fake inside fence")'
jcheck "rounds: status parsed despite reason line" "$J" 'd.rounds[3].status==="INTERRUPTED"'
jcheck "rounds: segments captured" "$J" 'd.rounds[3].segments.length===1 && d.rounds[3].segments[0]==="段落 探索\nseg body"'
jcheck "rounds: handoff keeps #### lines" "$J" 'd.rounds[1].handoff.startsWith("#### 現況")'
jcheck "rounds: line numbers" "$J" 'd.rounds[1].line===1 && d.rounds[1].file==="devlog.md"'
jcheck "rounds: no input by default" "$J" 'd.rounds.every(r => !("input" in r))'
jcheck "checkpoint_blocks: one block with body" "$J" 'd.checkpoint_blocks.length===1 && d.checkpoint_blocks[0].heading==="Checkpoint（Round 1-2）" && d.checkpoint_blocks[0].body.includes("keep it")'

J="$(bash "$SCRIPT_DIR/report-devlog.sh" --json --rounds --with-input)"
jcheck "with-input: input field present" "$J" 'd.rounds[1].input==="secret-input-text"'

# --- --json on NOT_STARTED ------------------------------------------------------
NS_ROOT="$(mktemp -d)"
J="$(CLAUDE_PROJECT_DIR="$NS_ROOT" bash "$SCRIPT_DIR/report-devlog.sh" --json)"
jcheck "json NOT_STARTED" "$J" 'd.started===false'
rm -rf "$NS_ROOT"

# @@JSON_TESTS@@

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
