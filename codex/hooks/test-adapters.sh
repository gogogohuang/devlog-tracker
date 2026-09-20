#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

# project-dir reads cwd, not workspace_roots
ROOT="$(printf '{"cwd":"%s"}' "$TMP" | bash "$SCRIPT_DIR/project-dir.sh")"
if [ "$ROOT" = "$TMP" ]; then echo "PASS: project-dir reads cwd"; else echo "FAIL: project-dir [$ROOT]"; FAIL=1; fi

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
OUT="$(printf '{"cwd":"%s","how":"startup"}' "$TMP/project" | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$OUT" in *"Round 1"*) echo "PASS: sessionStart injects context" ;; *) echo "FAIL: sessionStart [$OUT]"; FAIL=1 ;; esac

# userPromptSubmit: opens a Round in .round-current.md
SUBMIT="$TMP/submit"
mkdir -p "$SUBMIT/.devlog"
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
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{},"session_id":"codex-1"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 2 ]; then echo "PASS: expired tool blocked (exit 2)"; else echo "FAIL: preTool exit [$RC]"; FAIL=1; fi

set +e
printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/.devlog/.round-current.md"},"session_id":"codex-1"}' "$SUBMIT" "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 0 ]; then echo "PASS: devlog write allowed (exit 0)"; else echo "FAIL: allowed-tool exit [$RC]"; FAIL=1; fi

# stop: blocks (exit 2) while the round is unfinished
printf '{"round": 1, "opened_at": "now"}\n' > "$SUBMIT/.devlog/.round-open"
cksum < "$SUBMIT/.devlog/.round-current.md" > "$SUBMIT/.devlog/.turn-start"
set +e
printf '{"cwd":"%s"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-stop.sh" >/dev/null 2>/dev/null
RC=$?
set -e
if [ "$RC" -eq 2 ]; then echo "PASS: stop blocks unfinished round (exit 2)"; else echo "FAIL: stop exit [$RC]"; FAIL=1; fi

# sessionEnd: closes the open round using "why" (not "reason")
printf '\n## Round 2 — now\n\n### Status\nIN_PROGRESS\n' > "$SUBMIT/.devlog/.round-current.md"
printf '{"round": 2, "opened_at": "now"}\n' > "$SUBMIT/.devlog/.round-open"
cksum < "$SUBMIT/.devlog/.round-current.md" > "$SUBMIT/.devlog/.turn-start"
printf '{"cwd":"%s","why":"windowClosed"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-session-end.sh" >/dev/null
if grep -q 'SessionEnd:windowClosed' "$SUBMIT/.devlog/devlog.md" 2>/dev/null; then
  echo "PASS: sessionEnd closes round via 'why'"
else
  echo "FAIL: sessionEnd 'why' fallback"; FAIL=1
fi

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

# sessionStart: payload with neither "how" nor "source" falls back to startup and still injects
OUT="$(printf '{"cwd":"%s"}' "$TMP/project" | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$OUT" in *"Round 1"*) echo "PASS: sessionStart falls back to startup without how/source" ;; *) echo "FAIL: sessionStart no-source [$OUT]"; FAIL=1 ;; esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1
fi
