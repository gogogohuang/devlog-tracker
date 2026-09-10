# Compact / keep scripts Implementation Plan

> **HISTORICAL.** Part of the 0.4→0.5 batch (`optimization-plans.md`). Do not re-execute.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move compact and keep with bash so range cuts, write-before-delete, Checkpoint rules, and full-keep checkpoint reset are not LLM-authored. Commands still propose range/name and wait for confirm.

**Architecture:** `devlog-md.sh` (sourced) splits fence-aware `## ` blocks. `compact-devlog.sh` and `keep-move.sh` are user-invoked (may `exit 1`). Commands call the scripts after confirm. Full keep zeros `rounds_since_checkpoint` (overrides `commands/keep.md` "不要動 `.checkpoint-state`").

**Tech Stack:** bash, awk, existing assert-and-exit tests.

## Global Constraints

- Write destination first; delete from `devlog.md` only after the destination contains the expected `## Round` headings. Delete-first is forbidden.
- Compact never reads/writes `devlog.<name>.md`. Keep never writes `devlog.archive.md`.
- Open Round (`.round-open` `round` if the file exists; otherwise keep with no `.round-open` treats every Round as historical) is never moved by keep.
- Compact retains: preamble, last 5 rounds, unfinished (`IN_PROGRESS`/`BLOCKED`/`INTERRUPTED`), all `## Checkpoint`.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- Command copy is Traditional Chinese.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- If `json-field.sh` exists, keep uses it to set `.round-open` `round` and checkpoint counter; otherwise copy today's grep/awk.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/devlog-md.sh` | fence-aware block split / status / checkpoint range |
| `hooks/scripts/compact-devlog.sh` | archive move |
| `hooks/scripts/keep-move.sh` | `--from --to --name` |
| `hooks/scripts/test-compact-devlog.sh` | compact cases |
| `hooks/scripts/test-keep-move.sh` | keep cases including full-keep checkpoint reset |
| `commands/compact.md` | confirm then run script |
| `commands/keep.md` | propose (LLM) then run `keep-move.sh` |
| `docs/design/keep.md` | full keep resets checkpoint counter |

---

### Task 1: compact script + tests

**Files:**
- Create: `hooks/scripts/devlog-md.sh`, `hooks/scripts/compact-devlog.sh`, `hooks/scripts/test-compact-devlog.sh`

**Interfaces:**
- `compact-devlog.sh` uses `CLAUDE_PROJECT_DIR`. Stdout: `MOVED=<n> REMAINING=<n> ARCHIVE=<n>`. Exit 0 if nothing to move (`MOVED=0`). Exit 1 if `devlog.md` missing.

- [ ] **Step 1: Write failing `hooks/scripts/test-compact-devlog.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
mkdir -p "$TMP/.devlog"
FAIL=0
assert_eq() {
  local d="$1" e="$2" a="$3"
  if [ "$e" = "$a" ]; then echo "PASS: $d"; else echo "FAIL: $d expected [$e] got [$a]"; FAIL=1; fi
}

# missing log
bash "$SCRIPT_DIR/compact-devlog.sh" >/dev/null
assert_eq "missing log exit 1" "1" "$?"

round() {
  local n="$1" st="$2"
  cat >> "$TMP/.devlog/devlog.md" <<EOF
## Round ${n} — 2026-09-09T12:00:00+08:00

### Summary
s${n}

### Handoff
#### 現況
h${n}

### Status
${st}
EOF
}

: > "$TMP/.devlog/devlog.md"
printf '%s\n\n' '# preamble' >> "$TMP/.devlog/devlog.md"
n=1
while [ "$n" -le 8 ]; do round "$n" DONE; n=$((n+1)); done
round 9 IN_PROGRESS
cat >> "$TMP/.devlog/devlog.md" <<'EOF'
## Checkpoint（Round 1-3 摘要）
cp body
EOF

OUT="$(bash "$SCRIPT_DIR/compact-devlog.sh")"
assert_eq "compact exit 0" "0" "$?"
echo "$OUT" | grep -q 'MOVED=3' && echo "PASS: moved 1-3" || { echo "FAIL: $OUT"; FAIL=1; }
grep -q '# preamble' "$TMP/.devlog/devlog.md" && echo "PASS: preamble stays" || { echo "FAIL: preamble"; FAIL=1; }
grep -q '## Checkpoint' "$TMP/.devlog/devlog.md" && echo "PASS: checkpoint stays" || { echo "FAIL: cp"; FAIL=1; }
grep -q '## Round 9' "$TMP/.devlog/devlog.md" && echo "PASS: in-progress stays" || { echo "FAIL: r9"; FAIL=1; }
grep -q '## Round 4' "$TMP/.devlog/devlog.md" && echo "PASS: last-5 keep 4" || { echo "FAIL: r4"; FAIL=1; }
grep -q '## Round 1' "$TMP/.devlog/devlog.archive.md" && echo "PASS: archive has 1" || { echo "FAIL: archive"; FAIL=1; }
grep -q '## Round 9' "$TMP/.devlog/devlog.archive.md" && { echo "FAIL: archived in-progress"; FAIL=1; } || echo "PASS: did not archive 9"
test -f "$TMP/.devlog/devlog.foo.md" && { echo "FAIL: touched keep file"; FAIL=1; } || echo "PASS: no keep file"

# second compact is idempotent on remaining last-5+unfinished
OUT2="$(bash "$SCRIPT_DIR/compact-devlog.sh")"
echo "$OUT2" | grep -q 'MOVED=0' && echo "PASS: second compact moves 0" || { echo "FAIL: $OUT2"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: Run — expect FAIL** (`compact-devlog.sh` missing)

```bash
bash hooks/scripts/test-compact-devlog.sh
```

- [ ] **Step 3: Implement `devlog-md.sh` + `compact-devlog.sh`**

`devlog-md.sh` must provide (sourced):

- `devlog_list_round_starts FILE` → lines `NR N` for each unfenced `## Round N`
- `devlog_block_end FILE START` → last NR of that block (next unfenced `## ` minus 1, or EOF)
- `devlog_round_status FILE START END` → last non-empty line after unfenced `### Status` in that range, or empty

`compact-devlog.sh`:

1. Exit 1 if `$DEVLOG_DIR/devlog.md` missing.
2. Identify round starts fence-aware.
3. Mark keep: last 5 round numbers; any round whose status is IN_PROGRESS|BLOCKED|INTERRUPTED; every Checkpoint block; preamble before first Round.
4. Remaining DONE rounds go to a temp archive append, then temp main without those blocks.
5. Verify archive temp contains those `## Round` headings; then `cat archive_temp >> devlog.archive.md` (create if needed) and `mv` main temp onto `devlog.md`.
6. Print `MOVED=… REMAINING=… ARCHIVE=…` (archive count = unfenced `## Round` in archive file).

Keep the scripts fail-closed on I/O (`set -uo pipefail`; `exit 1` if `mv` fails after archive write — do not delete main if archive append failed).

- [ ] **Step 4: Tests pass**

```bash
bash hooks/scripts/test-compact-devlog.sh
```

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/devlog-md.sh hooks/scripts/compact-devlog.sh hooks/scripts/test-compact-devlog.sh
git commit -m "$(cat <<'EOF'
feat: compact devlog.md with a deterministic script

EOF
)"
```

---

### Task 2: keep-move script + tests

**Files:**
- Create: `hooks/scripts/keep-move.sh`, `hooks/scripts/test-keep-move.sh`
- Modify: `docs/design/keep.md` known limitation 1 (full keep **does** zero the counter)

**Interfaces:**
- `keep-move.sh --from N --to M --name SLUG`
- Reject: missing log, from>to, name `archive`, name with `/` `\` `..`, empty, would write `devlog.md`, name longer than 64, range includes open round, target file exists, a round in range missing.
- Full keep = every historical round is in from–to. Then leftover open Round heading → `## Round 1`; delete `.span-open`; if `.round-open` exists set `"round"` to 1; set `rounds_since_checkpoint` to 0 (do not change `max_silent_rounds`).
- Episode keep: delete `.span-open` only if its `round` is inside from–to.
- Checkpoint move rules: copy from current `commands/keep.md` section 5.

- [ ] **Step 1: Write `test-keep-move.sh`** covering: missing log exit 1; episode keep writes named file then removes those rounds; open round not moved; refuse overwrite; full keep renames leftover to Round 1 and `rounds_since_checkpoint` is 0.

Fixture sketch for full keep:

```bash
export CLAUDE_PROJECT_DIR="$TMP"
# rounds 1-2 DONE, round 3 open skeleton, .round-open round 3, checkpoint-state rounds_since_checkpoint 19
bash "$SCRIPT_DIR/keep-move.sh" --from 1 --to 2 --name episode
# assert leftover heading is ## Round 1
# assert json rounds_since_checkpoint 0
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `keep-move.sh`** using `devlog-md.sh`. Write named file with provenance header from `commands/keep.md` section 6, then verify, then rewrite `devlog.md`.

- [ ] **Step 4: Tests pass**

- [ ] **Step 5: In `docs/design/keep.md`, replace known limitation 1** with: "Full keep zeros `rounds_since_checkpoint` and does not change `max_silent_rounds`."

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/keep-move.sh hooks/scripts/test-keep-move.sh docs/design/keep.md
git commit -m "$(cat <<'EOF'
feat: move keep ranges with a script and reset checkpoint on full keep

EOF
)"
```

---

### Task 3: Point commands at the scripts

**Files:**
- Modify: `commands/compact.md` — after reading rules, run `compact-devlog.sh`; relay stdout; do not hand-edit files.
- Modify: `commands/keep.md` — steps 1–4 (propose/wait/validate) stay LLM; step 5–6 become: run `keep-move.sh --from --to --name` with confirmed values. Delete the hand-written move algorithm from the command (script is source of truth). Keep the confirm prompt verbatim.

- [ ] **Step 1: compact.md** replace steps 4–6 file edits with:

```markdown
4. 跑（不要自己搬檔）：
   ```bash
   CLAUDE_PROJECT_DIR="$(pwd)" bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/compact-devlog.sh"
   ```
   檔案不存在時腳本 exit 1：告知沒有東西可壓縮。
5. 用 stdout 的 `MOVED` / `REMAINING` / `ARCHIVE` 回報一句話。
```

- [ ] **Step 2: keep.md** after validation, replace sections 5–6 with invoke `keep-move.sh`. On exit 1, print stderr and do not retry a delete. Section 7 (Summary/Handoff on open Round) stays.

- [ ] **Step 3: Grep** `compact-devlog.sh` in compact.md and `keep-move.sh` in keep.md.

- [ ] **Step 4: Commit**

```bash
git add commands/compact.md commands/keep.md
git commit -m "$(cat <<'EOF'
feat: compact and keep commands call the move scripts

EOF
)"
```

