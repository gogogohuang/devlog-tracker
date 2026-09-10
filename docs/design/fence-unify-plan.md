# Fence unify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One fence-open rule everywhere: lines matching `^[ \t]*```` toggle fence state, so indented fences hide fake `##` headings for keep/compact/`devlog-md` the same way enforce already does.

**Architecture:** Introduce a single awk snippet or sourced comment constant used by `devlog-md.sh`, and update inline awk in `keep-move.sh` / `compact-devlog.sh` to the same regex. Add a `test-devlog-md.sh` case for indented fences if not already present; extend keep/compact tests if they only cover column-0 fences.

**Tech Stack:** bash, awk.

## Global Constraints

- Spec: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) §4.
- Canonical fence toggle: `/^[ \t]*```` (same as `enforce-devlog.sh`).
- Do not change Summary/Handoff substance rules or Stop logic beyond shared fence awareness.
- Do not bump version.
- This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/devlog-md.sh` | All fence toggles use indented-aware regex |
| `hooks/scripts/keep-move.sh` | Same |
| `hooks/scripts/compact-devlog.sh` | Same |
| `hooks/scripts/test-devlog-md.sh` | Indented fence hides `## Round` |
| `hooks/scripts/test-keep-move.sh` and/or `test-compact-devlog.sh` | One indented-fence regression each if missing |

---

### Task 1: Failing test — indented fence

**Files:**
- Modify: `hooks/scripts/test-devlog-md.sh`

- [ ] **Step 1: Add case**

```bash
# Indented fence must hide ## Round N from list_round_starts
cat > "$TMP/indent.md" <<'EOF'
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
# Note: the fixture must use real leading spaces before ``` on the fence lines.
OUT="$(devlog_list_round_starts "$TMP/indent.md")"
echo "$OUT" | grep -q ' 1$' || { echo "FAIL: missing round 1"; FAIL=1; }
echo "$OUT" | grep -q ' 2$' || { echo "FAIL: missing round 2"; FAIL=1; }
echo "$OUT" | grep -q '99' && { echo "FAIL: fenced round 99 counted"; FAIL=1; } || echo "PASS: indented fence hides Round 99"
```

Use a here-doc that actually indents the fence with spaces (four spaces before \`\`\`text and closing \`\`\`).

- [ ] **Step 2: Run — expect FAIL** on current `^````-only `devlog-md.sh`.

```bash
bash hooks/scripts/test-devlog-md.sh
```

---

### Task 2: Unify fence regex

**Files:**
- Modify: `hooks/scripts/devlog-md.sh`
- Modify: `hooks/scripts/keep-move.sh`
- Modify: `hooks/scripts/compact-devlog.sh`

- [ ] **Step 1: In every awk fence toggle in these three files**, replace `/^\`\`\`/` with `/^[ \t]*\`\`\`/`.

Also fix `devlog_insert_before_summary`'s `$0 ~ /^\`\`\`` / `$0 ~ /^\`\`\`` style checks to the indented form.

Do **not** change `enforce-devlog.sh` / `session-start-devlog.sh` / `close-open-round.sh` unless they still use column-0 only (they should already be indented-aware — leave them if already `/^[ \t]*````).

- [ ] **Step 2: Tests**

```bash
bash hooks/scripts/test-devlog-md.sh
bash hooks/scripts/test-keep-move.sh
bash hooks/scripts/test-compact-devlog.sh
bash hooks/scripts/run-tests.sh
```

- [ ] **Step 3: Optional keep/compact fixture**

If keep/compact tests have no indented-fence case, add one minimal fixture proving a fenced `## Round` inside an indented fence is not moved/compacted as a real round.

- [ ] **Step 4: Commit**

```bash
git add hooks/scripts/devlog-md.sh hooks/scripts/keep-move.sh hooks/scripts/compact-devlog.sh \
  hooks/scripts/test-devlog-md.sh hooks/scripts/test-keep-move.sh hooks/scripts/test-compact-devlog.sh
git commit -m "$(cat <<'EOF'
fix: treat indented fences as fences in keep/compact/devlog-md

EOF
)"
```
