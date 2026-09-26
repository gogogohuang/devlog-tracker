#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

# project-dir reads cwd, not workspace_roots
ROOT="$(printf '{"cwd":"%s"}' "$TMP" | bash "$SCRIPT_DIR/project-dir.sh")"
if [ "$ROOT" = "$TMP" ]; then echo "PASS: project-dir reads cwd"; else echo "FAIL: project-dir [$ROOT]"; FAIL=1; fi

mkdir -p "$TMP/nested/.devlog-tracker" "$TMP/nested/src/lib"
ROOT="$(printf '{"cwd":"%s"}' "$TMP/nested/src/lib" | bash "$SCRIPT_DIR/project-dir.sh")"
if [ "$ROOT" = "$TMP/nested" ]; then echo "PASS: nested cwd resolves installed project"; else echo "FAIL: nested cwd [$ROOT]"; FAIL=1; fi

mkdir -p "$TMP/plugin-project/.git" "$TMP/plugin-project/src/lib"
ROOT="$(printf '{"cwd":"%s"}' "$TMP/plugin-project/src/lib" | bash "$SCRIPT_DIR/project-dir.sh")"
if [ "$ROOT" = "$TMP/plugin-project" ]; then echo "PASS: plugin nested cwd resolves git root"; else echo "FAIL: plugin nested cwd [$ROOT]"; FAIL=1; fi

# Codex Stop requires JSON stdout on a successful exit.
OUT="$(printf '{"cwd":"%s","hook_event_name":"Stop"}' "$TMP/nested" | bash "$SCRIPT_DIR/on-stop.sh")"
if [ "$OUT" = '{}' ]; then echo "PASS: inactive Stop returns JSON"; else echo "FAIL: inactive Stop output [$OUT]"; FAIL=1; fi

# sessionStart: injects last Round's content as plain stdout
mkdir -p "$TMP/project/.devlog"
cat > "$TMP/project/.devlog/devlog.md" <<'EOF'
## Round 1 — now

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
OUT="$(printf '{"cwd":"%s","source":"startup"}' "$TMP/project" | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$OUT" in *"Round 1"*) echo "PASS: sessionStart injects context" ;; *) echo "FAIL: sessionStart [$OUT]"; FAIL=1 ;; esac

# userPromptSubmit: opens a Round in .round-current.md
SUBMIT="$TMP/submit"
mkdir -p "$SUBMIT/.devlog" "$SUBMIT/.devlog-tracker" "$SUBMIT/src"
touch "$SUBMIT/.devlog/.enabled"
bash "$SCRIPT_DIR/on-user-prompt-submit.sh" <<EOF2 >/dev/null
{"cwd":"$SUBMIT","prompt":"hello","session_id":"codex-1"}
EOF2
if grep -q 'hello' "$SUBMIT/.devlog/.round-current.md" 2>/dev/null; then
  echo "PASS: userPromptSubmit writes round"
else
  echo "FAIL: userPromptSubmit round"; FAIL=1
fi

# preTool: blocks (exit 2) once the silence window has expired, allows fresh writes
NOW="$(date +%s)"
OLD=$((NOW - 1000))
SUM="$(cksum < "$SUBMIT/.devlog/.round-current.md" | tr -d '\n')"
printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "max_silent_seconds": 900, "session_id": "codex-1"}\n' "$OLD" "$SUM" > "$SUBMIT/.devlog/.segment-state"
set +e
ERR="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{},"session_id":"codex-1"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh" 2>&1 >/dev/null)"
RC=$?
set -e
if [ "$RC" -eq 2 ]; then echo "PASS: expired tool blocked (exit 2)"; else echo "FAIL: preTool exit [$RC]"; FAIL=1; fi
case "$ERR" in
  *'cat '*'apply_patch'*) echo "PASS: Codex block explains recovery tools" ;;
  *) echo "FAIL: Codex recovery guidance [$ERR]"; FAIL=1 ;;
esac

set +e
printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/.devlog/.round-current.md"},"session_id":"codex-1"}' "$SUBMIT" "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 0 ]; then echo "PASS: devlog write allowed (exit 0)"; else echo "FAIL: allowed-tool exit [$RC]"; FAIL=1; fi

set +e
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"cat %s/.devlog/.round-current.md"},"session_id":"codex-1"}' \
  "$SUBMIT" "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 0 ]; then echo "PASS: devlog cat allowed"; else echo "FAIL: devlog cat exit [$RC]"; FAIL=1; fi

set +e
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"cat %s/.devlog/.round-current.md; echo unsafe"},"session_id":"codex-1"}' \
  "$SUBMIT" "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 2 ]; then echo "PASS: chained cat blocked"; else echo "FAIL: chained cat exit [$RC]"; FAIL=1; fi

# Codex reports file edits as apply_patch with the patch in tool_input.command.
PATCH='*** Begin Patch
*** Update File: .devlog/.round-current.md
@@
-before
+after
*** End Patch'
set +e
printf '{"cwd":"%s","tool_name":"apply_patch","tool_input":{"command":%s},"session_id":"codex-1"}' \
  "$SUBMIT" "$(node -p 'JSON.stringify(process.argv[1])' "$PATCH")" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 0 ]; then echo "PASS: devlog apply_patch allowed"; else echo "FAIL: devlog apply_patch exit [$RC]"; FAIL=1; fi

PATCH='*** Begin Patch
*** Update File: ../.devlog/.round-current.md
@@
-before
+after
*** End Patch'
set +e
printf '{"cwd":"%s","tool_name":"apply_patch","tool_input":{"command":%s},"session_id":"codex-1"}' \
  "$SUBMIT/src" "$(node -p 'JSON.stringify(process.argv[1])' "$PATCH")" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 0 ]; then echo "PASS: nested cwd devlog apply_patch allowed"; else echo "FAIL: nested cwd apply_patch exit [$RC]"; FAIL=1; fi

PATCH='*** Begin Patch
*** Update File: .devlog/.round-current.md
@@
-before
+after
*** End Patch'
set +e
printf '{"cwd":"%s","tool_name":"apply_patch","tool_input":{"command":%s},"session_id":"codex-1"}' \
  "$SUBMIT/src" "$(node -p 'JSON.stringify(process.argv[1])' "$PATCH")" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 2 ]; then echo "PASS: nested cwd unrelated apply_patch blocked"; else echo "FAIL: nested cwd unrelated patch exit [$RC]"; FAIL=1; fi

PATCH='*** Begin Patch
*** Update File: .devlog/.round-current.md
@@
-before
+after
*** Update File: src/main.js
@@
-before
+after
*** End Patch'
set +e
printf '{"cwd":"%s","tool_name":"apply_patch","tool_input":{"command":%s},"session_id":"codex-1"}' \
  "$SUBMIT" "$(node -p 'JSON.stringify(process.argv[1])' "$PATCH")" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 2 ]; then echo "PASS: mixed apply_patch blocked"; else echo "FAIL: mixed apply_patch exit [$RC]"; FAIL=1; fi

# stop: blocks (exit 2) while the round is unfinished
printf '{"round": 1, "opened_at": "now"}\n' > "$SUBMIT/.devlog/.round-open"
cksum < "$SUBMIT/.devlog/.round-current.md" > "$SUBMIT/.devlog/.turn-start"
set +e
printf '{"cwd":"%s"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-stop.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 2 ]; then echo "PASS: stop blocks unfinished round (exit 2)"; else echo "FAIL: stop exit [$RC]"; FAIL=1; fi

# sessionEnd: closes the open round using the documented "reason"
printf '\n## Round 2 — now\n\n### Status\nIN_PROGRESS\n' > "$SUBMIT/.devlog/.round-current.md"
printf '{"round": 2, "opened_at": "now"}\n' > "$SUBMIT/.devlog/.round-open"
cksum < "$SUBMIT/.devlog/.round-current.md" > "$SUBMIT/.devlog/.turn-start"
printf '{"cwd":"%s","reason":"other"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-session-end.sh" >/dev/null
if grep -q 'SessionEnd:other' "$SUBMIT/.devlog/devlog.md" 2>/dev/null; then
  echo "PASS: sessionEnd closes round via reason"
else
  echo "FAIL: sessionEnd reason"; FAIL=1
fi

# Interrupt closes the active round immediately, using Codex's event.
printf '\n## Round 3 — now\n\n### Status\nIN_PROGRESS\n' > "$SUBMIT/.devlog/.round-current.md"
printf '{"round": 3, "opened_at": "now"}\n' > "$SUBMIT/.devlog/.round-open"
cksum < "$SUBMIT/.devlog/.round-current.md" > "$SUBMIT/.devlog/.turn-start"
printf '{"cwd":"%s","hook_event_name":"Interrupt","turn_id":"turn-3"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-interrupt.sh" >/dev/null
if grep -q 'Interrupt:cancelled' "$SUBMIT/.devlog/devlog.md" 2>/dev/null; then
  echo "PASS: interrupt closes round"
else
  echo "FAIL: interrupt did not close round"; FAIL=1
fi

# SubagentStart gives a Codex subagent the existing Lessons Mode guidance.
touch "$SUBMIT/.devlog/.lessons-enabled"
OUT="$(printf '{"cwd":"%s","hook_event_name":"SubagentStart","agent_id":"child-1","agent_type":"general-purpose"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-subagent-start.sh")"
if printf '%s' "$OUT" | jq -e --arg p "$SUBMIT" '.hookSpecificOutput.hookEventName == "SubagentStart" and (.hookSpecificOutput.additionalContext | contains($p) and contains("lessons-append.sh"))' >/dev/null 2>&1; then
  echo "PASS: subagent receives Lessons Mode guidance"
else
  echo "FAIL: subagent guidance [$OUT]"; FAIL=1
fi

mkdir -p "$SUBMIT/.devlog-tracker/codex/hooks" "$SUBMIT/.devlog-tracker/core/scripts"
cp "$SCRIPT_DIR/on-subagent-start.sh" "$SCRIPT_DIR/project-dir.sh" "$SUBMIT/.devlog-tracker/codex/hooks/"
cp "$SCRIPT_DIR/../../core/scripts/lessons-subagent-start.sh" "$SCRIPT_DIR/../../core/scripts/json-field.sh" "$SUBMIT/.devlog-tracker/core/scripts/"
OUT="$(printf '{"cwd":"%s","hook_event_name":"SubagentStart","agent_id":"child-2","agent_type":"general-purpose"}' "$TMP/unrelated-worktree" | bash "$SUBMIT/.devlog-tracker/codex/hooks/on-subagent-start.sh")"
if printf '%s' "$OUT" | jq -e --arg p "$SUBMIT" '.hookSpecificOutput.additionalContext | contains($p)' >/dev/null 2>&1; then
  echo "PASS: worktree subagent guidance uses main project"
else
  echo "FAIL: worktree subagent guidance [$OUT]"; FAIL=1
fi
rm -f "$SUBMIT/.devlog/.lessons-enabled"

# fail-open: when ../../core/scripts is missing, preTool/stop wrappers must allow (exit 0)
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN/codex/hooks"
cp "$SCRIPT_DIR/on-pre-tool.sh" "$SCRIPT_DIR/on-stop.sh" "$SCRIPT_DIR/project-dir.sh" "$ORPHAN/codex/hooks/"
for W in on-pre-tool on-stop; do
  set +e
  printf '{"cwd":"%s"}' "$ORPHAN" | bash "$ORPHAN/codex/hooks/$W.sh" >/dev/null 2>/dev/null
  RC=$?
  set -e
  if [ "$RC" -eq 0 ]; then echo "PASS: $W fails open without core/scripts (exit 0)"; else echo "FAIL: $W orphan exit [$RC]"; FAIL=1; fi
done

# sessionStart: payload with neither "source" nor "how" falls back to startup and still injects
OUT="$(printf '{"cwd":"%s"}' "$TMP/project" | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$OUT" in *"Round 1"*) echo "PASS: sessionStart falls back to startup without how/source" ;; *) echo "FAIL: sessionStart no-source [$OUT]"; FAIL=1 ;; esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1
fi
