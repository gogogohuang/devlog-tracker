# SessionStart excerpt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `startup` / `resume` / `compact` / `fork`, inject the last Checkpoint plus the last two Rounds' Summary / Handoff / Status, using fence-aware parsing. Do not inject on `clear`. Do not empty new sessions.

**Architecture:** Replace the `MAX_ROUNDS=8` full-buffer awk in `session-start-devlog.sh` with a fence-aware excerpt. Align the inject *content* with `commands/continue.md` (recent rounds + last Checkpoint), not the empty-clear path.

**Tech Stack:** bash, awk, existing `test-session-start-devlog.sh`.

## Global Constraints

- `source=clear` stays silent after heal (0.4.0). Do not revert that.
- Do not inject `### 段落` or full `### User Input` when `### Summary` exists.
- If the last Round has no `### Summary` (skeleton), include its `### User Input` and `### Status` so a crash is visible.
- Last Checkpoint = last fence-aware line matching `^## Checkpoint`.
- Preamble (text before the first unfenced `## Round`) is **not** injected (it can be huge; continue already tells Claude to read the file).
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- If `hook-json-helper-plan.md` already landed, keep using `json-field.sh` for the span note; this plan does not require it.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/session-start-devlog.sh` | Excerpt printer |
| `hooks/scripts/test-session-start-devlog.sh` | New scenarios 13+ |
| `skills/devlog-tracker/SKILL.md` | "最近 8 輪" → excerpt wording |
| `README.md` | "最近幾輪" stays; no "8" |
| `docs/design/continue.md` | Table "last 8 rounds" → "excerpt" |
| `docs/design/summary-handoff.md` | Out-of-scope bullet about the 8-round window |

---

### Task 1: Failing excerpt tests

**Files:**
- Modify: `hooks/scripts/test-session-start-devlog.sh` (append before the final `FAIL` summary)

**Interfaces:**
- Consumes: `session-start-devlog.sh` stdout on `source=startup`
- Produces: assertions listed below

- [ ] **Step 1: Append scenarios**

Add a helper at the top if missing:

```bash
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
```

Before the final `if [ "$FAIL" -eq 0 ]` block, reset the log and add:

```bash
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
```

Also change Scenario 2 if it currently requires the raw heading line only — it should still pass because Round 1 Summary-less fixtures in early tests may only have `## Round 1`. If Scenario 2's file is just one heading line, excerpt should still print `Round 1`.

- [ ] **Step 2: Run tests (expect FAIL on 13–15)**

```bash
bash hooks/scripts/test-session-start-devlog.sh
```

Expected: Scenario 13 fails (`secret intermediate` or `Round 6` still present).

---

### Task 2: Implement excerpt

**Files:**
- Modify: `hooks/scripts/session-start-devlog.sh` from the `MAX_ROUNDS=8` awk through `exit 0`

**Interfaces:**
- Stdout intro line must contain `接手摘要` (tests can assert this optional; Scenario 13 uses Round numbers).
- Span warning (non-clear) unchanged.

- [ ] **Step 3: Replace the awk block**

Delete `MAX_ROUNDS=8`. After the span warning and `[ -f "$DEVLOG_FILE" ] || exit 0`, print:

```bash
echo "以下是本專案 .devlog/devlog.md 的接手摘要（不是全文；完整紀錄請自行讀取原檔）："
echo ""
awk '
  /^[ \t]*```/ { fence = !fence }
  {
    lines[NR] = $0
    infence[NR] = fence
  }
  END {
    n = NR
    last_cp = 0
    rc = 0
    for (i = 1; i <= n; i++) {
      if (infence[i]) continue
      if (lines[i] ~ /^## Checkpoint/) last_cp = i
      if (lines[i] ~ /^## Round /) { rc++; round_at[rc] = i }
    }
    if (last_cp > 0) {
      cp_end = n
      for (j = last_cp + 1; j <= n; j++) {
        if (!infence[j] && lines[j] ~ /^## /) { cp_end = j - 1; break }
      }
      for (j = last_cp; j <= cp_end; j++) print lines[j]
      print ""
    }
    start_i = (rc > 2) ? rc - 1 : 1
    if (rc == 0) exit 0
    for (r = start_i; r <= rc; r++) {
      rs = round_at[r]
      re = n
      for (j = rs + 1; j <= n; j++) {
        if (!infence[j] && lines[j] ~ /^## /) { re = j - 1; break }
      }
      print lines[rs]
      print ""
      has_summary = 0
      for (j = rs; j <= re; j++) if (!infence[j] && lines[j] ~ /^### Summary/) has_summary = 1
      keep = 0
      for (j = rs + 1; j <= re; j++) {
        if (infence[j]) {
          if (keep) print lines[j]
          continue
        }
        if (lines[j] ~ /^### Summary/ || lines[j] ~ /^### Handoff/ || lines[j] ~ /^### Status/) { keep = 1; print lines[j]; continue }
        if (lines[j] ~ /^### User Input/) { keep = (has_summary ? 0 : 1); if (keep) print lines[j]; continue }
        if (lines[j] ~ /^### /) { keep = 0; continue }
        if (keep) print lines[j]
      }
      print ""
    }
  }
' "$DEVLOG_FILE" 2>/dev/null || true
exit 0
```

- [ ] **Step 4: Run tests**

```bash
bash hooks/scripts/test-session-start-devlog.sh
```

Expected: `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/session-start-devlog.sh hooks/scripts/test-session-start-devlog.sh
git commit -m "$(cat <<'EOF'
feat: inject a SessionStart excerpt instead of the last eight full rounds

EOF
)"
```

---

### Task 3: Docs

**Files:**
- Modify: `skills/devlog-tracker/SKILL.md` (自動注入 numbered list item 1: 「只取最近 8 輪」)
- Modify: `docs/design/continue.md` (intro + table header "last 8 rounds")
- Modify: `docs/design/summary-handoff.md` Out of scope "Changing SessionStart's last 8 rounds window"

- [ ] **Step 1: SKILL**

Replace:

```markdown
1. 腳本讀取 `.devlog/devlog.md`，只取最近 8 輪（避免整份塞爆 context）
```

with:

```markdown
1. 腳本讀取 `.devlog/devlog.md`，注入最後一個 `## Checkpoint`（若有）加上最近 2 輪的 Summary / Handoff / Status（沒有 Summary 的 skeleton 才帶 User Input）
```

- [ ] **Step 2: continue.md**

Replace "still injects the last 8 rounds, as before" with "still injects the SessionStart excerpt (last Checkpoint + last two Rounds' close), as `session-start-devlog.sh` does".

Table column "Inject last 8 rounds + span note" → "Inject excerpt + span note".

- [ ] **Step 3: summary-handoff.md**

In Out of scope, delete the bullet "Changing SessionStart's "last 8 rounds" window or compact's retain rules." and insert:

```markdown
- Changing compact's retain rules.
```

- [ ] **Step 4: Commit**

```bash
git add skills/devlog-tracker/SKILL.md docs/design/continue.md docs/design/summary-handoff.md
git commit -m "$(cat <<'EOF'
docs: describe SessionStart excerpt instead of eight full rounds

EOF
)"
```

