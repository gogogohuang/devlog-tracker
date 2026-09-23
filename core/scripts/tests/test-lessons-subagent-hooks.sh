#!/usr/bin/env bash
# Self-check for lessons-subagent-start.sh (SubagentStart) and
# lessons-subagent-done.sh (PostToolUse Agent|Task). Run:
#   bash core/scripts/tests/test-lessons-subagent-hooks.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"

FAIL=0
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (missing: $needle)"; FAIL=1 ;;
  esac
}
assert_empty() {
  local desc="$1" out="$2"
  if [ -z "$out" ]; then echo "PASS: $desc"; else echo "FAIL: $desc (got: $out)"; FAIL=1; fi
}
assert_valid_json() {
  local desc="$1" out="$2"
  if ! command -v jq >/dev/null 2>&1; then echo "SKIP: $desc (no jq)"; return 0; fi
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then echo "PASS: $desc"; else echo "FAIL: $desc (invalid JSON: $out)"; FAIL=1; fi
}

START_IN='{"session_id":"s1","cwd":"/elsewhere/.claude/worktrees/agent-x","agent_id":"a1","agent_type":"general-purpose","hook_event_name":"SubagentStart"}'
SYNC_DONE='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"p"},"tool_response":{"status":"completed","content":[{"type":"text","text":"done"}]}}'
ASYNC_DONE='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"p"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"a1"}}'
NESTED_DONE='{"session_id":"s1","agent_id":"a1","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"p"},"tool_response":{"status":"completed"}}'

# --- disabled: both hooks silent -------------------------------------------
OUT="$(printf '%s' "$START_IN" | bash "$SCRIPT_DIR/lessons-subagent-start.sh")"
assert_empty "start: .enabled absent -> silent" "$OUT"
OUT="$(printf '%s' "$SYNC_DONE" | bash "$SCRIPT_DIR/lessons-subagent-done.sh")"
assert_empty "done: .enabled absent -> silent" "$OUT"

touch "$DEVLOG_DIR/.enabled"
OUT="$(printf '%s' "$START_IN" | bash "$SCRIPT_DIR/lessons-subagent-start.sh")"
assert_empty "start: lessons off -> silent" "$OUT"
OUT="$(printf '%s' "$SYNC_DONE" | bash "$SCRIPT_DIR/lessons-subagent-done.sh")"
assert_empty "done: lessons off -> silent" "$OUT"

touch "$DEVLOG_DIR/.lessons-enabled"

# --- SubagentStart: inject lessons-append.sh instructions with absolute paths
OUT="$(printf '%s' "$START_IN" | bash "$SCRIPT_DIR/lessons-subagent-start.sh")"
assert_valid_json "start: output is valid JSON" "$OUT"
assert_contains "start: hookEventName SubagentStart" '"hookEventName":"SubagentStart"' "$OUT"
assert_contains "start: additionalContext present" '"additionalContext":' "$OUT"
assert_contains "start: pins the main project dir, not the agent cwd" "DEVLOG_PROJECT_DIR='$TMP_ROOT'" "$OUT"
assert_contains "start: absolute lessons-append.sh path" "$SCRIPT_DIR/lessons-append.sh" "$OUT"
assert_contains "start: asks to mention it in the final report" "最終回報" "$OUT"

# relative CLAUDE_PROJECT_DIR still resolves to an absolute path
(cd "$TMP_ROOT" && OUT="$(printf '%s' "$START_IN" | CLAUDE_PROJECT_DIR=. bash "$SCRIPT_DIR/lessons-subagent-start.sh")"
 case "$OUT" in *"DEVLOG_PROJECT_DIR='$TMP_ROOT'"*|*"DEVLOG_PROJECT_DIR='$(pwd -P)'"*) echo "PASS: start: relative project dir made absolute" ;;
   *) echo "FAIL: start: relative project dir not made absolute ($OUT)"; exit 1 ;; esac) || FAIL=1

# path needing JSON escaping stays valid JSON
QDIR="$TMP_ROOT/we\"ird"
mkdir -p "$QDIR/.devlog"
touch "$QDIR/.devlog/.enabled" "$QDIR/.devlog/.lessons-enabled"
OUT="$(printf '%s' "$START_IN" | CLAUDE_PROJECT_DIR="$QDIR" bash "$SCRIPT_DIR/lessons-subagent-start.sh")"
assert_valid_json "start: quote in project path still valid JSON" "$OUT"

# --- PostToolUse(Agent): foreground completion only -------------------------
OUT="$(printf '%s' "$SYNC_DONE" | bash "$SCRIPT_DIR/lessons-subagent-done.sh")"
assert_valid_json "done: output is valid JSON" "$OUT"
assert_contains "done: hookEventName PostToolUse" '"hookEventName":"PostToolUse"' "$OUT"
assert_contains "done: sub agent advisory" "[Lessons Mode 提示] sub agent 完成" "$OUT"

OUT="$(printf '%s' "$ASYNC_DONE" | bash "$SCRIPT_DIR/lessons-subagent-done.sh")"
assert_empty "done: async launch -> silent (task-notification covers it)" "$OUT"

OUT="$(printf '%s' "$NESTED_DONE" | bash "$SCRIPT_DIR/lessons-subagent-done.sh")"
assert_empty "done: nested (agent_id set) -> silent" "$OUT"

OUT="$(printf '%s' 'not json' | bash "$SCRIPT_DIR/lessons-subagent-done.sh")"
RC=$?
[ "$RC" -eq 0 ] && echo "PASS: done: garbage stdin fails open" || { echo "FAIL: done: garbage stdin exit $RC"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
