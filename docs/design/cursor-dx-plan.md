# Cursor DX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cursor without jq still forwards `session_id` into `round-start`; commands resolve plugin root via `CLAUDE_PLUGIN_ROOT` then `DEVLOG_TRACKER_ROOT`; README documents how to run existing commands from Cursor.

**Architecture:** Fix the no-jq branch in `on-submit-prompt.sh` (TDD via `cursor/hooks/test-adapters.sh`). Normalize command markdown to a single `PLUGIN_ROOT=…` line. README Cursor section gets a manual command table. No Cursor slash packaging.

**Tech Stack:** bash, optional jq, Markdown commands.

## Global Constraints

- Spec: [`polish-0.9.0-design.md`](polish-0.9.0-design.md) §2.
- Out of scope: Cursor-only slash commands, StopFailure adapter, cloud sessionStart workaround, mapping Cursor sessionStart to clear/compact/fork.
- Do not mention `/devlog-tracker:checkpoint` in README yet (plan 7).
- Do not bump version.
- This plan lives under `docs/design/`.

## File Structure

| File | Responsibility |
|---|---|
| `cursor/hooks/on-submit-prompt.sh` | Always include `session_id` in payload when extractable |
| `cursor/hooks/test-adapters.sh` | Assert no-jq path stores session_id into `.segment-state` via round-start |
| `commands/*.md` | `PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$DEVLOG_TRACKER_ROOT}"` before script paths |
| `README.md` | Cursor: env + hooks merge + manual bash for existing commands |

---

### Task 1: No-jq `session_id` (TDD)

**Files:**
- Modify: `cursor/hooks/test-adapters.sh`
- Modify: `cursor/hooks/on-submit-prompt.sh`

**Interfaces:**
- Consumes: Cursor `beforeSubmitPrompt` JSON with `workspace_roots`, `prompt`, `session_id`.
- Produces: payload `{"prompt":"…","session_id":"…"}` into `round-start.sh` even when `jq` is absent; stdout still `{"continue":true}`.

- [ ] **Step 1: Add failing self-check**

Append to `cursor/hooks/test-adapters.sh` (before the final FAIL exit). Use `env PATH=…` only for this invocation so the rest of the file keeps the normal PATH.

```bash
# --- no-jq session_id must reach segment-state via round-start ------------
NOJQ_HOME="$TMP/nojq_home"
mkdir -p "$NOJQ_HOME/.devlog" "$TMP/nojq_path"
touch "$NOJQ_HOME/.devlog/.enabled"
CLEAN_PATH="$TMP/nojq_path"
for cmd in bash sh cksum date grep sed cat mkdir tr mktemp rm head awk touch pwd dirname uname; do
  src="$(command -v "$cmd" || true)"
  [ -n "$src" ] && ln -sf "$src" "$CLEAN_PATH/$cmd"
done
# Explicitly do NOT link jq. Add any other binaries round-start needs if the
# adapter fails to start (inspect stderr by removing >/dev/null temporarily).
OUT="$(printf '{"workspace_roots":["%s"],"prompt":"nojq-hi","session_id":"cursor-nojq"}' "$NOJQ_HOME" \
  | env PATH="$CLEAN_PATH" bash "$SCRIPT_DIR/on-submit-prompt.sh")"
case "$OUT" in *'"continue":true'*) echo "PASS: nojq submit continues" ;; *) echo "FAIL: nojq submit [$OUT]"; FAIL=1 ;; esac
# round-start persists session_id into .segment-state when enabled
SEG_SID="$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$NOJQ_HOME/.devlog/.segment-state" 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
if [ "$SEG_SID" = "cursor-nojq" ]; then
  echo "PASS: nojq session_id stored in segment-state"
else
  echo "FAIL: nojq session_id missing (got [$SEG_SID])"; FAIL=1
fi
```

If `CLEAN_PATH` is too minimal for `round-start.sh` on the agent OS, extend the `for cmd in …` list until the adapter produces `continue:true` and writes a round; still must not include `jq`.
- [ ] **Step 2: Run — expect FAIL**

```bash
bash cursor/hooks/test-adapters.sh
```

Expected: `FAIL: nojq session_id missing` (current no-jq payload omits `session_id`).

- [ ] **Step 3: Implement no-jq branch**

Replace the else branch in `cursor/hooks/on-submit-prompt.sh` with:

```bash
else
  PROMPT="$(printf '%s' "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  # Escape only what we embed; prompts with quotes remain a known no-jq limitation (plan out of scope).
  PAYLOAD="$(printf '{"prompt":"%s","session_id":"%s"}' "$PROMPT" "$SESSION_ID")"
fi
```

Keep the jq branch unchanged.

- [ ] **Step 4: Run — expect PASS**

```bash
bash cursor/hooks/test-adapters.sh
bash hooks/scripts/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add cursor/hooks/on-submit-prompt.sh cursor/hooks/test-adapters.sh
git commit -m "$(cat <<'EOF'
fix: forward session_id in Cursor beforeSubmitPrompt without jq

EOF
)"
```

---

### Task 2: Command PLUGIN_ROOT fallback

**Files:**
- Modify: every file under `commands/` that invokes `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/…`

- [ ] **Step 1: Replace invocation pattern**

In each such command file, immediately before the bash line(s), document:

```markdown
先決定 plugin 根目錄（有 `CLAUDE_PLUGIN_ROOT` 用它；否則用 `DEVLOG_TRACKER_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄）：

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVLOG_TRACKER_ROOT:-}}"
CLAUDE_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/hooks/scripts/<script>.sh" …
```
```

Apply to: `start.md`, `pause.md`, `status.md`, `span.md`, `segment-watch.md`, `compact.md`, `keep.md`, `clean.md`, `resume.md`, and any other command that still hard-codes only `CLAUDE_PLUGIN_ROOT`. Keep existing confirm / NOT_STARTED behavior. Do not invent new scripts.

For `start.md`, keep the gitignore ask flow; only change how the script path is resolved.

- [ ] **Step 2: Commit**

```bash
git add commands/
git commit -m "$(cat <<'EOF'
docs: resolve plugin scripts via CLAUDE_PLUGIN_ROOT or DEVLOG_TRACKER_ROOT

EOF
)"
```

---

### Task 3: README Cursor manual commands

**Files:**
- Modify: `README.md` Cursor section

- [ ] **Step 1: Extend Cursor section**

After the existing install / cloud-agent notes, add a subsection that states:

1. Set `DEVLOG_TRACKER_ROOT` to the plugin absolute path; merge `cursor/hooks.json` into the project `.cursor/hooks.json`.
2. Cursor has no `/devlog-tracker:*` slash surface — run the same scripts as commands, e.g.:

```bash
export DEVLOG_TRACKER_ROOT=/absolute/path/to/devlog-tracker
export CLAUDE_PROJECT_DIR="$(pwd)"
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/start-devlog.sh"
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/status-devlog.sh"
bash "$DEVLOG_TRACKER_ROOT/hooks/scripts/segment-watch-set.sh" 600
# pause / span-open / span-close / compact / keep-move / clean / resume：見 commands/*.md
```

3. Do **not** list checkpoint (ships in plan 7).

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: document Cursor manual script invocations

EOF
)"
```
