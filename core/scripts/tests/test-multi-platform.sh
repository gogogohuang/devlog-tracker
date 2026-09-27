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

# --- Task 4: the other platform's open round survives, numbers are unique -
new_project interleave
printf '%s\n' '{"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 600, "session_id": ""}' > "$D/.segment-state"
submit claude "claude task" >/dev/null
# shellcheck disable=SC2034 # read inside check's eval strings
OUT="$(submit codex "codex task")"
check "claude round still open" '[ -f "$D/.round-open" ] && grep -q "claude task" "$D/.round-current.md"'
check "claude round not INTERRUPTED" '! grep -q INTERRUPTED "$D/.round-current.md" && [ ! -s "$D/devlog.md" ]'
check "claude heading has no suffix" 'head -1 "$D/.round-current.md" | grep -q "^## Round 1 — " && ! head -1 "$D/.round-current.md" | grep -q " · "'
check "codex reserved round 2 with suffix" 'grep -q "^## Round 2 — .* · codex$" "$D/.round-current@codex.md"'
check "codex told its file" 'case "$OUT" in *".devlog/.round-current@codex.md"*) true ;; *) false ;; esac'
submit cursor "cursor task" >/dev/null
check "cursor reserved round 3" 'grep -q "^## Round 3 — .* · cursor$" "$D/.round-current@cursor.md"'

# Codex's own next prompt closes only codex's round.
submit codex "codex second" >/dev/null
check "codex dangling round merged as INTERRUPTED" 'grep -q "^## Round 2 — .* · codex$" "$D/devlog.md" && grep -q INTERRUPTED "$D/devlog.md"'
check "claude still open after codex re-submit" 'grep -q "claude task" "$D/.round-current.md"'
check "codex second is round 4" 'grep -q "^## Round 4 — .* · codex$" "$D/.round-current@codex.md"'
check "non-claude segment state seeded" '[ ! -f "$D/.segment-state" ] || [ -f "$D/.segment-state@codex" ]'

# Reply Fold finds codex's round by number even when it is not last.
new_project fold
cat > "$D/devlog.md" <<'EOF'
## Round 1 — 2026-09-27T10:00:00+0800 · codex

### Summary
asked a question

### Reply
q?

### Handoff
<handoff>
<state>
waiting
</state>
</handoff>

### Status
DONE

## Round 2 — 2026-09-27T10:02:00+0800

### Summary
claude work

### Reply
ok

### Handoff
<handoff>
<state>
done
</state>
</handoff>

### Status
DONE
EOF
printf '{"round": 1, "opened_at": "t"}\n' > "$D/.awaiting-reply@codex"
submit codex "the answer" >/dev/null
check "fold reopened codex round 1" 'grep -q "^## Round 1 — .* · codex$" "$D/.round-current@codex.md" && grep -q "the answer" "$D/.round-current@codex.md"'
check "claude round 2 stays in devlog" 'grep -q "^## Round 2 " "$D/devlog.md" && ! grep -q "^## Round 1 " "$D/devlog.md"'

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
