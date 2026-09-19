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
"$NODE_BIN" "$REPO_ROOT/bin/devlog-tracker.js" init --codex --cursor >/dev/null 2>"$TMP/stderr" \
  || { echo "FAIL: init exited non-zero"; cat "$TMP/stderr"; FAIL=1; }

[ -f "$PROJECT/.devlog-tracker/VERSION" ] && echo "PASS: vendored VERSION exists" || { echo "FAIL: no VERSION"; FAIL=1; }
[ -f "$PROJECT/.devlog-tracker/env.sh" ] && echo "PASS: vendored env.sh exists" || { echo "FAIL: no env.sh"; FAIL=1; }
[ -f "$PROJECT/.codex/hooks.json" ] && echo "PASS: .codex/hooks.json written" || { echo "FAIL: no .codex/hooks.json"; FAIL=1; }
[ -f "$PROJECT/.agents/skills/devlog-start/SKILL.md" ] && echo "PASS: Codex start skill written" || { echo "FAIL: no Codex start skill"; FAIL=1; }
[ -f "$PROJECT/.cursor/hooks.json" ] && echo "PASS: .cursor/hooks.json written" || { echo "FAIL: no .cursor/hooks.json"; FAIL=1; }

# re-running must not duplicate entries
COUNT_BEFORE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROJECT/.codex/hooks.json')).hooks.Stop.length)")
"$NODE_BIN" "$REPO_ROOT/bin/devlog-tracker.js" init --codex --cursor >/dev/null 2>"$TMP/stderr" \
  || { echo "FAIL: second init exited non-zero"; cat "$TMP/stderr"; FAIL=1; }
COUNT_AFTER=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROJECT/.codex/hooks.json')).hooks.Stop.length)")
if [ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; then
  echo "PASS: re-running init does not duplicate hook entries"
else
  echo "FAIL: hook entries duplicated ($COUNT_BEFORE -> $COUNT_AFTER)"; FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1
fi
