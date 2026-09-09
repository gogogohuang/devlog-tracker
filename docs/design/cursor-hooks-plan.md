# Cursor hooks adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the same bash hook scripts from Cursor Agent hooks so a Cursor workspace can enforce the same `.devlog/` loop.

**Architecture:** Thin adapters under `cursor/hooks/` translate Cursor JSON stdin/stdout to the Claude Code scripts. Consumers copy or merge `cursor/hooks.json` into the project `.cursor/hooks.json`. Do not replace Claude `hooks/hooks.json`.

**Tech Stack:** bash, Cursor hooks (`sessionStart`, `beforeSubmitPrompt`, `preToolUse`, `stop`, `sessionEnd`, `postToolUseFailure`). Docs: https://cursor.com/docs/hooks

## Global Constraints

- Set `CLAUDE_PROJECT_DIR` from Cursor `workspace_roots[0]`. If missing, `.`.
- Cursor `sessionStart` is fire-and-forget and injects via JSON `additional_context`, not raw stdout. Adapter wraps `session-start-devlog.sh` output.
- Cursor `stop` does not retry via exit 2. If `enforce-devlog.sh` exits 2, adapter prints `{"followup_message":"<stderr>"}`. Set `"loop_limit": 1` to match this plugin's one-shot guard. Map `loop_count >= 1` to Claude `stop_hook_active: true`.
- Cursor `stop` `status` `aborted` / `error` → `close-open-round.sh` with that reason; `completed` → enforce.
- `beforeSubmitPrompt` always `"continue": true`. Side effect: run `round-start.sh` with `{"prompt":...}`.
- `preToolUse`: run `segment-watch.sh`; exit 2 → `{"permission":"deny","user_message":"<stderr>"}`.
- Cloud agents skip `sessionStart` — document it; do not invent a workaround.
- Do not bump version. Batch release is **0.5.0** after all optimization plans (`docs/design/version-0.5.0-plan.md`).
- This repo gitignores `docs/superpowers/`. This plan lives under `docs/design/`.
- README: Cursor is optional; Claude Code remains the primary install.

## File Structure

| File | Responsibility |
|---|---|
| `cursor/hooks.json` | version 1 map of events → adapter commands |
| `cursor/hooks/project-dir.sh` | `cursor_project_dir` from stdin JSON |
| `cursor/hooks/on-session-start.sh` | additional_context JSON |
| `cursor/hooks/on-submit-prompt.sh` | round-start |
| `cursor/hooks/on-pre-tool.sh` | segment-watch |
| `cursor/hooks/on-stop.sh` | enforce or close-open |
| `cursor/hooks/on-session-end.sh` | on-session-end.sh |
| `cursor/hooks/on-tool-failure.sh` | on-tool-failure.sh |
| `cursor/hooks/test-adapters.sh` | stdin fixtures, no Cursor binary |
| `README.md` | Cursor install |
| `docs/design/recording-moments.md` | Out of scope "Cursor hook ports" → done, with cloud sessionStart gap |

Adapter `command` paths in `cursor/hooks.json` are relative to the **consumer project** after copy, e.g. `"command": "bash cursor/hooks/on-stop.sh"` if the plugin files are vendored into the repo, **or** document:

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [{ "command": "bash ${DEVLOG_TRACKER_ROOT}/cursor/hooks/on-session-start.sh" }],
    "beforeSubmitPrompt": [{ "command": "bash ${DEVLOG_TRACKER_ROOT}/cursor/hooks/on-submit-prompt.sh" }],
    "preToolUse": [{ "command": "bash ${DEVLOG_TRACKER_ROOT}/cursor/hooks/on-pre-tool.sh" }],
    "stop": [{ "command": "bash ${DEVLOG_TRACKER_ROOT}/cursor/hooks/on-stop.sh", "loop_limit": 1 }],
    "sessionEnd": [{ "command": "bash ${DEVLOG_TRACKER_ROOT}/cursor/hooks/on-session-end.sh" }],
    "postToolUseFailure": [{ "command": "bash ${DEVLOG_TRACKER_ROOT}/cursor/hooks/on-tool-failure.sh" }]
  }
}
```

For tests, adapters locate Claude scripts at `"$(cd "$(dirname "$0")/../.." && pwd)/hooks/scripts"` when this repo is the plugin root (this repo's `cursor/hooks` → `../../hooks/scripts`).

---

### Task 1: project-dir + sessionStart adapter tests

- [ ] **Step 1: `test-adapters.sh`**

Fixture: `workspace_roots: ["/tmp/proj"]`, `devlog.md` with one Round, run `on-session-start.sh`, stdout JSON has `"additional_context"` containing `接手摘要` or `Round` (depending on whether excerpt plan has landed — assert `Round` which both old and new inject).

Empty workspace / no `.devlog` → `additional_context` omitted or empty string; still valid JSON; exit 0.

- [ ] **Step 2: Implement `project-dir.sh` + `on-session-start.sh`**

```bash
# on-session-start.sh
INPUT="$(cat)"
ROOT="$(printf '%s' "$INPUT" | bash "$(dirname "$0")/project-dir.sh")"
export CLAUDE_PROJECT_DIR="$ROOT"
# Claude script expects source=startup for inject
EXCERPT="$(printf '%s' '{"source":"startup"}' | bash "$PLUGIN_SCRIPTS/session-start-devlog.sh" 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$EXCERPT" '{additional_context:$c}'
else
  # escape quotes in excerpt for a minimal JSON string
  esc="$(printf '%s' "$EXCERPT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')"
  printf '{"additional_context":"%s"}\n' "$esc"
fi
```

`project-dir.sh` reads stdin JSON: jq `.workspace_roots[0] // empty`, else `.`.

- [ ] **Commit** `feat: add Cursor sessionStart adapter`

---

### Task 2: submit, preTool, stop, sessionEnd, tool failure

- [ ] **`on-submit-prompt.sh`**: jq `.prompt`, feed `round-start.sh`, print `{"continue":true}`.
- [ ] **`on-pre-tool.sh`**: pass stdin through to `segment-watch.sh` (Cursor `tool_name` / `tool_input.file_path` may differ — map `Write`/`StrReplace` to Claude `Write`/`Edit` when `file_path` ends with `.devlog/devlog.md`). If mapping is uncertain, pass through as-is and add a test that Cursor-style `{"tool_name":"Write","tool_input":{"file_path":"/tmp/proj/.devlog/devlog.md"}}` is allowlisted when expired (extend `segment-watch.sh` allowlist if needed: already suffix-matches `/.devlog/devlog.md`).
- [ ] **`on-stop.sh`**: read `status` and `loop_count`. If `aborted` or `error`, `close-open-round.sh "$status"` and print `{}`. If `completed`, build stdin for enforce: `{"stop_hook_active": true}` when `loop_count` is a positive integer, else `{}`. Capture stderr; if enforce exit 2, `jq -n --arg m "$stderr" '{followup_message:$m}'`.
- [ ] **`on-session-end.sh`**: `close-open-round.sh` via existing `on-session-end.sh` with `CLAUDE_PROJECT_DIR` set. Cursor reason from `.reason`.
- [ ] **`on-tool-failure.sh`**: if `.is_interrupt == true` or Cursor equivalent, write `.interrupted` using existing script (pipe a JSON object with `is_interrupt: true`).
- [ ] Tests for stop: enforce-fail fixture → followup_message contains `Summary`; loop_count 1 → enforce sees active and exit 0 with empty followup.
- [ ] Commit `feat: wire Cursor prompt, tool, and stop adapters`

---

### Task 3: hooks.json + README

- [ ] Add `cursor/hooks.json` with the six events and `loop_limit: 1` on stop.
- [ ] README section **Cursor**：把 `cursor/hooks.json` 合併進專案 `.cursor/hooks.json`，並保證 `cursor/hooks/*.sh` 與 plugin `hooks/scripts` 相對路徑可用；或設 `DEVLOG_TRACKER_ROOT`。說明 cloud agent 沒有 sessionStart。
- [ ] recording-moments Out of scope: delete "Cursor hook ports"; add known limitation: cloud `sessionStart` does not run.
- [ ] Commit `docs: document Cursor hook install`

