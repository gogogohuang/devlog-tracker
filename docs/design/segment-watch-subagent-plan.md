# Segment Watch subagent skip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Do not block subagent tool calls with the parent round's 15-minute Segment Watch valve.

**Architecture:** `round-start.sh` stores `session_id` from UserPromptSubmit stdin into `.segment-state`. `segment-watch.sh` applies the valve only when stdin `session_id` is missing (legacy payload → current behavior) or equals the stored id. A different `session_id` exits 0.

**Tech Stack:** bash, existing segment-watch tests.

## Global Constraints

- Fail-open: unreadable JSON, missing `session_id` on PreToolUse → **keep today's valve** (do not skip). Skipping only when both ids are non-empty and differ.
- Do not require `### 段落` from a subagent.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- If `json-field.sh` exists, use `json_str_get` / `json_str_set` for `session_id`. The field is a quoted string.
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- Update `docs/design/segment-watch.md` known limitation "Subagent tool calls share the parent round's valve".

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/round-start.sh` | persist `session_id` |
| `hooks/scripts/segment-watch.sh` | compare ids |
| `hooks/scripts/test-segment-watch.sh` | new scenarios |
| `hooks/scripts/test-round-start.sh` | state contains session_id when stdin has it |
| `docs/design/segment-watch.md` | spec |

Default `.segment-state` in `commands/start.md` / `start-devlog.sh` if present should include `"session_id": ""` so `json_str_set` can replace it. If the key is missing, `json_str_set` no-ops — then round-start must write a full JSON object when adding the key (append via rewriting the object). Implement round-start so a missing key still gets written: if `json_str_get` is empty after set attempt, rewrite the file with the four original keys plus `session_id`.

---

### Task 1: Failing tests

- [ ] **Step 1: In `test-segment-watch.sh`**, after the existing expired+Bash blocks, add:

Parent id stored, PreToolUse stdin `{"tool_name":"Bash","session_id":"aaa"}` while state `session_id` is `aaa` and timer expired → still exit 2.

Same expired state, stdin `{"tool_name":"Bash","session_id":"bbb"}` → exit 0.

Expired state, stdin without `session_id` → exit 2 (legacy).

Seed `.segment-state` with `session_id` in the fixture JSON. If round-start is how production writes it, also add a `test-round-start.sh` case: stdin `{"prompt":"hi","session_id":"s1"}` results in `"session_id": "s1"` in `.segment-state`.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
bash hooks/scripts/test-segment-watch.sh
```

---

### Task 2: Implement

- [ ] **Step 1: `round-start.sh`** parse `session_id` like `prompt` (jq `.session_id // empty`, else grep). After the existing segment-state update, set `session_id`.

- [ ] **Step 2: `segment-watch.sh`** after `.enabled` check:

```bash
STORED="$(json_str_get "$SEGMENT_FILE" session_id 2>/dev/null || true)"
INCOMING=""
if command -v jq >/dev/null 2>&1; then
  INCOMING="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  [ "$INCOMING" = "null" ] && INCOMING=""
fi
if [ -n "$STORED" ] && [ -n "$INCOMING" ] && [ "$STORED" != "$INCOMING" ]; then
  exit 0
fi
```

If `json-field.sh` is not sourced yet, use grep for `session_id` on the state file (same pattern as `opened_at`).

- [ ] **Step 3: Tests pass** (`test-segment-watch.sh`, `test-round-start.sh`)

- [ ] **Step 4: Spec** replace the subagent limitation with: valve skips when PreToolUse `session_id` differs from the id stored at UserPromptSubmit.

- [ ] **Step 5: Commit** `feat: skip Segment Watch for other session_id values`

