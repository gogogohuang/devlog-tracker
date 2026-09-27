#!/usr/bin/env bash
# Two platforms in one worktree (docs/design/multi-platform-concurrency.md).
# Run: bash core/scripts/tests/test-multi-platform.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

new_project() {
  P="$TMP_ROOT/$1"
  mkdir -p "$P/.devlog"
  git -C "$P" init -q
  git -C "$P" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
  git -C "$P" branch -M main
  echo '.devlog/' > "$P/.gitignore"
  git -C "$P" add .gitignore
  git -C "$P" -c user.email=t@t.t -c user.name=t commit -q -m ignore
  touch "$P/.devlog/.enabled" "$P/.devlog/.platform-claimed"
  # shellcheck disable=SC2034 # read inside check's eval strings
  D="$P/.devlog"
}
submit() { # platform prompt
  printf '{"prompt":"%s","session_id":"%s-1"}' "$2" "$1" \
    | DEVLOG_PLATFORM="$1" DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/round-start.sh"
}

# --- Task 3: codex writes only @codex files ---------------------------------
new_project refactor
submit codex "hello from codex" >/dev/null
check "codex round file" '[ -f "$D/.round-current@codex.md" ] && grep -q "hello from codex" "$D/.round-current@codex.md"'
check "codex marker" '[ -f "$D/.round-open@codex" ] && [ -f "$D/.turn-start@codex" ]'
check "claude files untouched" '[ ! -e "$D/.round-current.md" ] && [ ! -e "$D/.round-open" ] && [ ! -e "$D/.turn-start" ]'

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
