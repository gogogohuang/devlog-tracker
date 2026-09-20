#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }

PROJECT="$TMP/project"
mkdir -p "$PROJECT"

cd "$PROJECT" || exit 1
NODE_BIN="$(command -v node)"
"$NODE_BIN" "$REPO_ROOT/bin/devlog-tracker.js" init --claude --codex --cursor >/dev/null 2>"$TMP/stderr" \
  || { echo "FAIL: init exited non-zero"; cat "$TMP/stderr"; FAIL=1; }

[ -f "$PROJECT/.devlog-tracker/VERSION" ] && echo "PASS: vendored VERSION exists" || { echo "FAIL: no VERSION"; FAIL=1; }
[ -f "$PROJECT/.devlog-tracker/env.sh" ] && echo "PASS: vendored env.sh exists" || { echo "FAIL: no env.sh"; FAIL=1; }
[ -f "$PROJECT/.claude/settings.local.json" ] && echo "PASS: .claude/settings.local.json written" || { echo "FAIL: no .claude/settings.local.json"; FAIL=1; }
[ -f "$PROJECT/.claude/skills/devlog-start/SKILL.md" ] && echo "PASS: Claude start skill written" || { echo "FAIL: no Claude start skill"; FAIL=1; }
[ -f "$PROJECT/CLAUDE.md" ] && grep -q 'devlog-tracker:begin' "$PROJECT/CLAUDE.md" \
  && echo "PASS: CLAUDE.md fallback block written" || { echo "FAIL: no devlog-tracker block in CLAUDE.md"; FAIL=1; }
[ -f "$PROJECT/.codex/hooks.json" ] && echo "PASS: .codex/hooks.json written" || { echo "FAIL: no .codex/hooks.json"; FAIL=1; }
[ -f "$PROJECT/.agents/skills/devlog-start/SKILL.md" ] && echo "PASS: Codex start skill written" || { echo "FAIL: no Codex start skill"; FAIL=1; }
[ -f "$PROJECT/.cursor/hooks.json" ] && echo "PASS: .cursor/hooks.json written" || { echo "FAIL: no .cursor/hooks.json"; FAIL=1; }

# Controller addition 1a: Check vendored core scripts exist
[ -f "$PROJECT/.devlog-tracker/core/scripts/enforce-devlog.sh" ] && echo "PASS: vendored core/scripts/enforce-devlog.sh exists" || { echo "FAIL: no core/scripts/enforce-devlog.sh"; FAIL=1; }
[ -f "$PROJECT/.devlog-tracker/claude/hooks.json" ] && echo "PASS: vendored claude/hooks.json exists" || { echo "FAIL: no claude/hooks.json"; FAIL=1; }

# Controller addition 1b: Check merged Claude hook commands are resolved (no placeholders)
if grep -q '\${CLAUDE_PLUGIN_ROOT\|${DEVLOG_TRACKER_ROOT' "$PROJECT/.claude/settings.local.json"; then
  echo "FAIL: unresolved placeholders in .claude/settings.local.json"; FAIL=1
else
  echo "PASS: no unresolved placeholders in .claude/settings.local.json"
fi

# Verify that Stop hook command references .devlog-tracker/core/scripts/
STOP_CMD=$("$NODE_BIN" -e "console.log(JSON.parse(require('fs').readFileSync('$PROJECT/.claude/settings.local.json')).hooks.Stop[0].hooks[0].command)")
if echo "$STOP_CMD" | grep -q '\.devlog-tracker/core/scripts/enforce-devlog\.sh'; then
  echo "PASS: Claude Stop hook references .devlog-tracker/core/scripts/enforce-devlog.sh"
else
  echo "FAIL: Claude Stop hook does not reference .devlog-tracker/core/scripts/enforce-devlog.sh"; FAIL=1
fi

# re-running must not duplicate entries
COUNT_BEFORE_CODEX=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROJECT/.codex/hooks.json')).hooks.Stop.length)")
COUNT_BEFORE_CLAUDE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROJECT/.claude/settings.local.json')).hooks.Stop.length)")
"$NODE_BIN" "$REPO_ROOT/bin/devlog-tracker.js" init --claude --codex --cursor >/dev/null 2>"$TMP/stderr" \
  || { echo "FAIL: second init exited non-zero"; cat "$TMP/stderr"; FAIL=1; }
COUNT_AFTER_CODEX=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROJECT/.codex/hooks.json')).hooks.Stop.length)")
COUNT_AFTER_CLAUDE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROJECT/.claude/settings.local.json')).hooks.Stop.length)")
if [ "$COUNT_BEFORE_CODEX" = "$COUNT_AFTER_CODEX" ]; then
  echo "PASS: re-running init does not duplicate Codex hook entries"
else
  echo "FAIL: Codex hook entries duplicated ($COUNT_BEFORE_CODEX -> $COUNT_AFTER_CODEX)"; FAIL=1
fi
if [ "$COUNT_BEFORE_CLAUDE" = "$COUNT_AFTER_CLAUDE" ]; then
  echo "PASS: re-running init does not duplicate Claude hook entries"
else
  echo "FAIL: Claude hook entries duplicated ($COUNT_BEFORE_CLAUDE -> $COUNT_AFTER_CLAUDE)"; FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1
fi
