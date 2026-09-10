# Segment Watch unblock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Segment Watch from causing wipe/death-spirals: (A) allow Read of `devlog.md` while expired so agents can append safely; (B) skip the valve for Claude Code dynamic-workflow / subagent tool calls that carry `agent_id` (they share the parent `session_id`, so the existing session_id skip is insufficient).

**Architecture:** Early-exit in `segment-watch.sh` when PreToolUse JSON has a non-empty top-level `agent_id`. Expand the expired allowlist to `Read` (and `Grep`) targeting `.devlog/devlog.md`. Tighten stderr + SKILL so unblock means append after Read, never full-file Write overwrite.

**Tech Stack:** bash hooks, `json-field.sh`, assert-and-exit tests.

## Global Constraints

- Spec index: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) § segment-watch-unblock; living behavior: [`segment-watch.md`](segment-watch.md).
- Claude Code: subagent / dynamic-workflow PreToolUse includes `agent_id`; main-thread omits it (docs since ~v2.1.69). Skip valve iff `agent_id` is non-empty after trim. Empty / missing / `"null"` → treat as main thread.
- Keep existing `session_id` differ → skip (other hosts).
- Expired allowlist paths: same suffix rule as today — exactly `.devlog/devlog.md` or ends with `/.devlog/devlog.md`. No `realpath`.
- Allowlisted tools while expired: existing `Write` / `Edit` / `StrReplace`, plus `Read`, plus `Grep`.
  - Path fields: prefer `tool_input.file_path`; if empty, also try `tool_input.path` (Grep often uses `path`).
- Do **not** allowlist Bash rewriting `devlog.md`.
- Do **not** auto-pause, invent Cursor-only fields, or score segment quality.
- Do not bump version (batch ends at `version-0.9.0-plan.md`).
- This plan lives under `docs/design/`.

## Exact stderr (when blocking)

Replace the current one-line message with:

```text
這一輪已經 ${ELAPSED} 秒沒有更新 .devlog/devlog.md（門檻 ${SEG_MAX} 秒）。請先 Read .devlog/devlog.md，再用 Edit 或 StrReplace **追加**一段「### 段落」（一行也可以）；禁止用 Write 覆寫整份檔。寫完再繼續呼叫其他工具。
```

## File Structure

| File | Responsibility |
|---|---|
| `hooks/scripts/segment-watch.sh` | `agent_id` skip; Read/Grep allowlist; new stderr |
| `hooks/scripts/test-segment-watch.sh` | new scenarios |
| `docs/design/segment-watch.md` | allowlist + agent_id + limitations |
| `skills/devlog-tracker/SKILL.md` | Round Segments valve instructions |
| `README.md` | one-line if it restates the valve unblock path |

---

### Task 1: Failing tests

**Files:**
- Modify: `hooks/scripts/test-segment-watch.sh`

**Interfaces:**
- Consumes: same fixture helpers as existing expired cases (`CLAUDE_PROJECT_DIR`, `.enabled`, `.segment-state`, stdin JSON).
- Produces: assertions below must FAIL on current `segment-watch.sh`.

- [ ] **Step 1: Add scenarios** (reuse the project’s existing expired-fixture setup; seed matching cksum + old epoch + `session_id: "aaa"`):

```bash
# --- expired + Read .devlog/devlog.md -> allowed ---
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":".devlog/devlog.md"},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Read devlog.md -> allowed" 0 $?

# --- expired + Read other file -> blocked ---
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Read other -> blocked" 2 $?

# --- expired + Grep path=.devlog/devlog.md -> allowed ---
printf '%s' '{"tool_name":"Grep","tool_input":{"path":".devlog/devlog.md","pattern":"Round"},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Grep devlog.md -> allowed" 0 $?

# --- expired + agent_id (dynamic workflow / subagent) -> allowed even for Bash ---
printf '%s' '{"tool_name":"Bash","tool_input":{},"session_id":"aaa","agent_id":"agent-xyz"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + agent_id -> allowed" 0 $?

# --- expired + empty agent_id string -> still blocked for Bash ---
printf '%s' '{"tool_name":"Bash","tool_input":{},"session_id":"aaa","agent_id":""}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + empty agent_id -> blocked" 2 $?

# --- stderr must mention Read + 禁止覆寫 ---
ERR="$(printf '%s' '{"tool_name":"Bash","tool_input":{},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" 2>&1 >/dev/null || true)"
case "$ERR" in
  *Read*.devlog/devlog.md*禁止*覆寫*) echo "PASS: stderr instructs Read then append" ;;
  *) echo "FAIL: stderr [$ERR]"; FAIL=1 ;;
esac
```

Keep all existing session_id / Write / StrReplace cases green.

- [ ] **Step 2: Run — expect FAIL**

```bash
bash hooks/scripts/test-segment-watch.sh
```

Expected: Read/Grep/agent_id cases fail (exit 2 instead of 0) and/or stderr assertion fails.

---

### Task 2: Implement skip + allowlist + stderr

**Files:**
- Modify: `hooks/scripts/segment-watch.sh`

- [ ] **Step 1: After the existing `session_id` differ-skip block**, add:

```bash
AGENT_ID="$(json_str_field "$INPUT" agent_id)"
[ "$AGENT_ID" = "null" ] && AGENT_ID=""
if [ -n "$AGENT_ID" ]; then
  exit 0
fi
```

- [ ] **Step 2: Unify path extraction** (before allowlist):

```bash
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo '')"
  [ "$FILE_PATH" = "null" ] && FILE_PATH=""
else
  FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
  if [ -z "$FILE_PATH" ]; then
    FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
  fi
fi
```

- [ ] **Step 3: Expand allowlist**

```bash
case "$TOOL_NAME" in
  Write|Edit|StrReplace|Read|Grep)
    case "$FILE_PATH" in
      .devlog/devlog.md|*/.devlog/devlog.md) exit 0 ;;
    esac
    ;;
esac
```

- [ ] **Step 4: Replace stderr** with the exact sentence in Global Constraints (use `${ELAPSED}` / `${SEG_MAX}`).

- [ ] **Step 5: Tests pass**

```bash
bash hooks/scripts/test-segment-watch.sh
bash hooks/scripts/run-tests.sh
```

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/segment-watch.sh hooks/scripts/test-segment-watch.sh
git commit -m "$(cat <<'EOF'
fix: skip segment-watch for agent_id; allow Read/Grep of devlog when expired

EOF
)"
```

---

### Task 3: Spec + SKILL

**Files:**
- Modify: `docs/design/segment-watch.md`
- Modify: `skills/devlog-tracker/SKILL.md`
- Modify: `README.md` only if it restates the unblock instruction

- [ ] **Step 1: `segment-watch.md`**

Update Mechanism allowlist bullet to include Read/Grep and `file_path`/`path`.

Add under Known Limitations / Subagent:

```markdown
- **Claude Code dynamic workflow / subagents.** They usually share the
  parent `session_id`, so session_id isolation alone does not skip them.
  When PreToolUse includes a non-empty `agent_id`, Segment Watch exits 0
  (subagents must not append parent-round `### 段落` under this valve).
  Main-thread calls omit `agent_id` and still hit the valve.
- **Unblock without wiping.** Expired main-thread may Read/Grep
  `.devlog/devlog.md`, then Edit/StrReplace to append. Full-file Write
  overwrite remains technically allowlisted for legacy paths but SKILL
  and stderr forbid it — prefer append.
```

- [ ] **Step 2: SKILL Round Segments valve paragraph**

Extend the existing 10-minute valve text so that when blocked, Claude must Read first, then Edit/StrReplace append a `### 段落`, and must not Write-overwrite the whole file. Note that Claude Code subagents with `agent_id` are not blocked by this valve.

- [ ] **Step 3: Commit**

```bash
git add docs/design/segment-watch.md skills/devlog-tracker/SKILL.md README.md
git commit -m "$(cat <<'EOF'
docs: document segment-watch agent_id skip and safe unblock path

EOF
)"
```
