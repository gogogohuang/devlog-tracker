# Heading substance Implementation Plan

> **HISTORICAL.** Part of the 0.4→0.5 batch (`optimization-plans.md`). Do not re-execute.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After the last Round has `### Summary` and `### Handoff` headings, require non-empty bodies, a legal Status, and `#### 下一步` when Status is `IN_PROGRESS` or `BLOCKED`.

**Architecture:** Extend the existing fence-aware last-Round extract in `enforce-devlog.sh`. Presence check stays first; substance checks run only if both headings exist. Loop guard and fail-open unchanged. Do not score prose.

**Tech Stack:** bash, grep, existing `test-enforce-devlog.sh`.

## Global Constraints

- Interrupt stubs (`這輪意外中斷。` / `這輪沒有正常收尾。`) are non-empty and must still pass.
- `INTERRUPTED` is a legal Status (hook-owned).
- Do not require `#### 決策` / `#### 檔案` / `#### 現況`.
- Do not require `#### 下一步` when Status is `DONE`.
- One-shot loop guard still exit 0 on retry even if substance is missing.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- Update `docs/design/summary-handoff.md` Known limitations / Out of scope to match.

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/enforce-devlog.sh` | Substance checks after heading presence |
| `hooks/scripts/test-enforce-devlog.sh` | Flip Scenario 4; add Status / 下一步 cases |
| `docs/design/summary-handoff.md` | Spec |
| `skills/devlog-tracker/SKILL.md` | One sentence: Stop also checks non-empty + Status |

---

### Task 1: Failing tests

**Files:**
- Modify: `hooks/scripts/test-enforce-devlog.sh`

**Interfaces:**
- Heading Scenario 4 today: empty bodies → allowed (exit 0). New expected: exit 2.
- New scenarios 12–14.

- [ ] **Step 1: Change Scenario 4 expected exit to 2**

Find:

```bash
assert_exit "both headings present with empty bodies -> allowed" 0 $?
```

Replace with:

```bash
assert_exit "both headings present with empty bodies -> blocked" 2 $?
EMPTY_MSG="$(echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"
case "$EMPTY_MSG" in
  *"是空的"*) echo "PASS: empty-body message" ;;
  *) echo "FAIL: empty-body stderr, got: $EMPTY_MSG"; FAIL=1 ;;
esac
```

Wait: the script already ran enforce once for `assert_exit`, consuming nothing extra — running it a second time is fine (hash still changed vs `.turn-start`). Do **not** capture stderr on the first call if `assert_exit` discards it; the extra call is OK.

- [ ] **Step 2: Append scenarios before the final FAIL summary**

```bash
# --- Heading Scenario 12: legal DONE with bodies, no 下一步 -> allowed ----
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'
### Summary
一句話。
### Handoff
#### 現況
做完了。
### Status
DONE
EOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "DONE with bodies and no 下一步 -> allowed" 0 $?

# --- Heading Scenario 13: IN_PROGRESS without 下一步 -> blocked -----------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
# reopen: round-start appends a skeleton; complete it without 下一步
LAST="$(awk '/^## Round /{n=$3} END{print n+0}' "$DEVLOG_DIR/devlog.md")"
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'
### Summary
還在做。
### Handoff
#### 現況
做到一半。
### Status
IN_PROGRESS
EOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "IN_PROGRESS without 下一步 -> blocked" 2 $?

# --- Heading Scenario 14: IN_PROGRESS with 下一步 -> allowed --------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'
### Summary
還在做。
### Handoff
#### 現況
做到一半。
#### 下一步
打開 foo.ts 繼續。
### Status
IN_PROGRESS
EOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "IN_PROGRESS with 下一步 -> allowed" 0 $?

# --- Heading Scenario 15: illegal Status -> blocked -----------------------
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'
### Summary
x
### Handoff
#### 現況
y
### Status
WIP
EOF
echo '{}' | bash "$SCRIPT_DIR/enforce-devlog.sh" >/dev/null 2>&1
assert_exit "illegal Status -> blocked" 2 $?
```

Scenario 13 is fragile because `round-start.sh` appends a **new** skeleton; the last Round is that skeleton, not the appended headings on a previous round. Match existing Heading Scenario 2 style: after `round-start.sh`, the last Round is a skeleton; `cat >>` appends headings **into that same file after the skeleton**, which is how Scenario 2 works today (it appends a full new `## Round` in some tests, or edits).

Look at Heading Scenario 2 in the current file and copy that fixture style: they `cat >>` a complete `## Round N` block after round-start (which already wrote a skeleton). That means the **last** Round is the one they appended, not the skeleton. Scenario 12–15 must `cat >>` a full `## Round` with the bodies under test, same as Scenario 4.

Use this fixture pattern for 12–15 (replace the bodies above):

```bash
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
cat >> "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 90 — 2026-09-09T10:40:00+08:00

### Summary
一句話。

### Handoff
#### 現況
做完了。

### Status
DONE
EOF
```

Pick unused Round numbers (90–93) so they are last.

- [ ] **Step 3: Run tests**

```bash
bash hooks/scripts/test-enforce-devlog.sh
```

Expected: Scenario 4 fails (still exit 0).

---

### Task 2: Implement checks

**Files:**
- Modify: `hooks/scripts/enforce-devlog.sh` immediately after the heading presence block that currently `exit 2` on missing titles, still inside `if [ -n "$LAST_ROUND" ]`

**Interfaces:**
- Helpers as inline bash, not a new file.

- [ ] **Step 1: Add helpers and checks**

After both headings are confirmed present:

```bash
section_body() {
  # stdin: LAST_ROUND; $1 heading regex like '^### Summary'
  local heading="$1"
  printf '%s\n' "$LAST_ROUND" | awk -v h="$heading" '
    $0 ~ h { grab=1; next }
    grab && /^### / { exit }
    grab && /^## / { exit }
    grab { print }
  '
}

nonempty_body() {
  section_body "$1" | grep -q '[^[:space:]]'
}

SUM_BODY_OK=0
HAN_BODY_OK=0
nonempty_body '^### Summary' && SUM_BODY_OK=1
nonempty_body '^### Handoff' && HAN_BODY_OK=1
if [ "$SUM_BODY_OK" -eq 0 ] || [ "$HAN_BODY_OK" -eq 0 ]; then
  echo "最後一個 Round 的 ### Summary 或 ### Handoff 是空的。請依 skills/devlog-tracker/SKILL.md 寫上內容（不要只留標題），寫在同一個 Round 裡，不要再新增一個 ## Round。" >&2
  exit 2
fi

STATUS_VAL="$(printf '%s\n' "$LAST_ROUND" | awk '
  /^### Status/ { grab=1; next }
  grab && /^### / { exit }
  grab && /^## / { exit }
  grab && $0 ~ /[^[:space:]]/ { print; exit }
')"
case "$STATUS_VAL" in
  DONE|IN_PROGRESS|BLOCKED|INTERRUPTED) ;;
  *)
    echo "### Status 必須是 DONE、IN_PROGRESS、BLOCKED、INTERRUPTED 其中一個。" >&2
    exit 2
    ;;
esac

if [ "$STATUS_VAL" = "IN_PROGRESS" ] || [ "$STATUS_VAL" = "BLOCKED" ]; then
  HAS_NEXT=0
  printf '%s\n' "$LAST_ROUND" | grep -q '^#### 下一步' && HAS_NEXT=1
  NEXT_OK=0
  if [ "$HAS_NEXT" -eq 1 ]; then
    printf '%s\n' "$LAST_ROUND" | awk '
      /^#### 下一步/ { grab=1; next }
      grab && /^#### / { exit }
      grab && /^### / { exit }
      grab && /^## / { exit }
      grab { print }
    ' | grep -q '[^[:space:]]' && NEXT_OK=1
  fi
  if [ "$NEXT_OK" -eq 0 ]; then
    echo "Status 是 IN_PROGRESS 或 BLOCKED 時，Handoff 必須有「#### 下一步」且後面有內容。" >&2
    exit 2
  fi
fi
```

- [ ] **Step 2: Run tests**

```bash
bash hooks/scripts/test-enforce-devlog.sh
```

Expected: `All checks passed.` Also re-run `test-on-interrupt.sh` and `test-close-open-round.sh` (stubs must still pass Stop).

```bash
bash hooks/scripts/test-close-open-round.sh
bash hooks/scripts/test-on-interrupt.sh
```

- [ ] **Step 3: Commit**

```bash
git add hooks/scripts/enforce-devlog.sh hooks/scripts/test-enforce-devlog.sh
git commit -m "$(cat <<'EOF'
feat: require non-empty Summary/Handoff and a legal Status on Stop

EOF
)"
```

---

### Task 3: Spec + skill sentence

**Files:**
- Modify: `docs/design/summary-handoff.md` Known limitations + Out of scope
- Modify: `skills/devlog-tracker/SKILL.md` paragraph "Stop hook 會檢查最後一個 Round 是否同時有 `### Summary` 與 `### Handoff`"

- [ ] **Step 1: Spec**

Replace Known limitation "Heading text is the only verified signal..." with:

```markdown
- **Presence plus a light structure check.** Headings must exist, Summary
  and Handoff bodies must contain a non-whitespace line, Status must be
  one of `DONE` / `IN_PROGRESS` / `BLOCKED` / `INTERRUPTED`, and
  `IN_PROGRESS` / `BLOCKED` require a non-empty `#### 下一步`. Prose
  quality is still on Claude.
```

In Out of scope, delete "Hook checks for subsection headings (`#### 決策` etc.), non-empty bodies, or Status/`下一步` consistency." and insert:

```markdown
- Hook checks for `#### 決策` / `#### 檔案` / `#### 現況`, or scoring
  Summary prose.
```

- [ ] **Step 2: SKILL**

Replace the sentence that says 只驗標題存在 with:

```markdown
Stop hook 會檢查最後一個 Round 是否同時有 `### Summary` 與 `### Handoff`、兩者底下有內容、`### Status` 是四個合法值之一，以及 `IN_PROGRESS`／`BLOCKED` 時 Handoff 有「下一步」。
```

- [ ] **Step 3: Commit**

```bash
git add docs/design/summary-handoff.md skills/devlog-tracker/SKILL.md
git commit -m "$(cat <<'EOF'
docs: Stop verifies empty headings and Status, not just titles

EOF
)"
```

