#!/usr/bin/env bash
# Two platforms in one worktree (docs/design/multi-platform-concurrency.md).
# Run: bash core/scripts/tests/test-multi-platform.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../workspace-snapshot.sh
. "$SCRIPT_DIR/workspace-snapshot.sh"
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

# --- Task 5: both Stop in either order, handoffs coexist -------------------
close_round() { # platform status file
  local f="$3"
  cat >> "$f" <<EOF

### Summary
closed by $1

### Reply
ok

### Handoff
<handoff>
<workspace>
$(workspace_snapshot "$P")
</workspace>
<state>
$1 state
</state>
<done-when>
tests pass
</done-when>
<next>
run \`bash core/scripts/run-tests.sh\`
</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- $1 decision
</decisions>
<open-questions>
- （無）
</open-questions>
<failed-attempts>
- （無）
</failed-attempts>
</session-handoff>
EOF
  # Replace the skeleton's Status with the requested one.
  awk -v st="$2" '/^### Status$/ { print; getline; print st; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  printf '{}' | DEVLOG_PLATFORM="$1" DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/enforce-devlog.sh"
}
new_project stops_claude_first
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
close_round claude IN_PROGRESS "$D/.round-current.md" 2>"$TMP_ROOT/err0"; rc=$?
check "claude-first: claude Stop passes" '[ "$rc" -eq 0 ] || { cat "$TMP_ROOT/err0"; false; }'
check "claude-first: claude merged, codex still open" 'grep -q "closed by claude" "$D/devlog.md" && [ -f "$D/.round-open@codex" ] && [ ! -e "$D/.round-open" ]'
close_round codex IN_PROGRESS "$D/.round-current@codex.md" 2>"$TMP_ROOT/err0"; rc=$?
check "claude-first: codex Stop passes" '[ "$rc" -eq 0 ] || { cat "$TMP_ROOT/err0"; false; }'
check "claude-first: numbers unique" '[ "$(grep -o "^## Round [0-9]*" "$D/devlog.md" | tr "\n" ",")" = "## Round 1,## Round 2," ]'
check "claude-first: neither INTERRUPTED" '! grep -q INTERRUPTED "$D/devlog.md"'

new_project stops
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
close_round codex IN_PROGRESS "$D/.round-current@codex.md" 2>"$TMP_ROOT/err1"; rc=$?
check "codex Stop passes" '[ "$rc" -eq 0 ] || { cat "$TMP_ROOT/err1"; false; }'
check "codex merged, claude still open" 'grep -q "closed by codex" "$D/devlog.md" && [ -f "$D/.round-open" ] && [ ! -e "$D/.round-open@codex" ]'
check "codex handoff written" 'grep -q "codex decision" "$D/handoff@codex.md"'
close_round claude IN_PROGRESS "$D/.round-current.md" 2>"$TMP_ROOT/err2"; rc=$?
check "claude Stop passes" '[ "$rc" -eq 0 ] || { cat "$TMP_ROOT/err2"; false; }'
check "file order is close order, numbers unique" '[ "$(grep -o "^## Round [0-9]*" "$D/devlog.md" | tr "\n" ",")" = "## Round 2,## Round 1," ]'
check "handoffs coexist" 'grep -q "claude decision" "$D/handoff.md" && grep -q "codex decision" "$D/handoff@codex.md"'
check "neither INTERRUPTED" '! grep -q INTERRUPTED "$D/devlog.md"'

OUT="$(printf '{"source":"startup"}' | DEVLOG_PLATFORM=codex DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/session-start-devlog.sh")"
check "codex SessionStart injects own handoff" 'case "$OUT" in *"codex decision"*) true ;; *) false ;; esac'
check "codex SessionStart does not inject claude handoff" 'case "$OUT" in *"claude decision"*) false ;; *) true ;; esac'
check "codex SessionStart notes claude handoff" 'case "$OUT" in *"另一個平台（claude）有未完成的交接：.devlog/handoff.md"*) true ;; *) false ;; esac'

# Interrupt of one platform does not touch the other.
new_project interrupt
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
DEVLOG_PLATFORM=codex DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/close-open-round.sh" "Interrupt:cancelled"
check "codex interrupted round merged" 'grep -q "^## Round 2 — .* · codex$" "$D/devlog.md" && grep -q "Interrupt:cancelled" "$D/devlog.md"'
check "claude untouched by codex interrupt" '[ -f "$D/.round-open" ] && grep -q "claude task" "$D/.round-current.md"'

# span-open falls back to the platform's own last round.
new_project span
printf '## Round 7 — t · codex\n\n### Status\nDONE\n\n## Round 8 — t\n\n### Status\nDONE\n' > "$D/devlog.md"
# shellcheck disable=SC2034 # read inside check's eval strings
OUT="$(DEVLOG_PLATFORM=codex DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/span-open.sh")"
check "codex span-open uses its own last round" '[ "$OUT" = "OPENED=7" ] && grep -q "\"round\": 7" "$D/.span-open@codex" && [ ! -e "$D/.span-open" ]'

# --- Task 6: whole-devlog commands --------------------------------------
new_project cmds
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed >/dev/null 2>"$TMP_ROOT/cleanerr"
check "clean refuses with two open rounds" '[ $? -ne 0 ] && grep -q "其他平台還有進行中的輪次" "$TMP_ROOT/cleanerr" && [ -f "$D/.round-current@codex.md" ]'
printf '## Round 9 — t\n\n### Status\nDONE\n' > "$D/devlog.md"
DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/keep-move.sh" --from 9 --to 9 --name x >/dev/null 2>"$TMP_ROOT/keeperr"
check "keep-move refuses with two open rounds" '[ $? -ne 0 ] && grep -q "其他平台還有進行中的輪次（codex）" "$TMP_ROOT/keeperr" && [ ! -e "$D/devlog.x.md" ]'

DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/pause-devlog.sh" >/dev/null
check "pause clears every platform's markers" '[ ! -e "$D/.round-open" ] && [ ! -e "$D/.round-open@codex" ]'

new_project clean1
printf '## Round 1 — t\n\n### Status\nDONE\n\n## Round 2 — t\n\n### Status\nDONE\n' > "$D/devlog.md"
submit codex "only codex" >/dev/null
check "codex got round 3 before clean" 'grep -q "^## Round 3 — .* · codex$" "$D/.round-current@codex.md"'
echo "old claude handoff" > "$D/handoff.md"
echo "old codex handoff" > "$D/handoff@codex.md"
DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed >/dev/null 2>&1
check "clean keeps the single open codex round as Round 1" 'grep -q "^## Round 1 — .* · codex$" "$D/.round-current@codex.md"'
check "clean removes every platform handoff" '[ ! -e "$D/handoff.md" ] && [ ! -e "$D/handoff@codex.md" ]'

# --- Span rounds are renumbered at merge when their number is taken -------
# A span-written round (no .round-open of its own) numbered by the LLM.
span_round() { # platform heading
  local f="$D/.round-current@$1.md" t="$D/.turn-start@$1"
  [ "$1" != claude ] || { f="$D/.round-current.md"; t="$D/.turn-start"; }
  printf '%s\n\n### User Input\n```text\nspan tick\n```\n\n### Status\nIN_PROGRESS\n' "$2" > "$f"
  echo stale > "$t"
  close_round "$1" IN_PROGRESS "$f" 2>"$TMP_ROOT/spanerr"
}
headings() { grep -o '^## Round .*' "$D/devlog.md" | sed 's/ — [^ ]*//' | tr '\n' ','; }

new_project renum_reserved
printf '## Round 1 — t\n\n### Status\nDONE\n' > "$D/devlog.md"
submit codex "codex task" >/dev/null
span_round claude "## Round 2 — 2026-09-28T10:00:00+0800"
# shellcheck disable=SC2034 # read inside check's eval strings
rc=$?
check "span claude round passes Stop" '[ "$rc" -eq 0 ] || { cat "$TMP_ROOT/spanerr"; false; }'
check "claude span round 2 renumbered past codex reservation" '[ "$(headings)" = "## Round 1,## Round 3," ]'
check "renumbered heading keeps its timestamp" 'grep -q "^## Round 3 — 2026-09-28T10:00:00+0800$" "$D/devlog.md"'
close_round codex IN_PROGRESS "$D/.round-current@codex.md" 2>"$TMP_ROOT/spanerr"
check "codex reserved round keeps 2" '[ "$(headings)" = "## Round 1,## Round 3,## Round 2 · codex," ]'

new_project renum_existing
printf '## Round 1 — t\n\n### Status\nDONE\n\n## Round 2 — t · codex\n\n### Status\nDONE\n\n## Round 3 — t\n\n### Status\nDONE\n' > "$D/devlog.md"
span_round claude "## Round 3 — t"
check "span round whose number exists gets the next free one" '[ "$(headings)" = "## Round 1,## Round 2 · codex,## Round 3,## Round 4," ]'

new_project renum_suffix
printf '## Round 4 — t\n\n### Status\nDONE\n' > "$D/devlog.md"
span_round codex "## Round 5 — t"
check "codex span round without suffix gets it on merge" '[ "$(headings)" = "## Round 4,## Round 5 · codex," ]'

new_project renum_passthrough
submit claude "claude task" >/dev/null
submit codex "codex task" >/dev/null
# shellcheck disable=SC2034 # read inside check's eval strings
BEFORE="$(head -1 "$D/.round-current.md")"
close_round claude IN_PROGRESS "$D/.round-current.md" 2>/dev/null
check "reserved round heading passes through unchanged" '[ "$(grep "^## Round " "$D/devlog.md")" = "$BEFORE" ]'

# --- Reply Fold prefers the caller's own round when numbers repeat ---------
new_project fold_dup
printf '## Round 5 — t · codex\n\n### Summary\ncodex asked\n\n### Status\nDONE\n\n## Round 5 — t\n\n### Summary\nclaude five\n\n### Status\nDONE\n' > "$D/devlog.md"
printf '{"round": 5, "opened_at": "t"}\n' > "$D/.awaiting-reply@codex"
submit codex "the answer" >/dev/null
check "codex fold reopens codex's Round 5" 'grep -q "codex asked" "$D/.round-current@codex.md" && grep -q "claude five" "$D/devlog.md" && ! grep -q "codex asked" "$D/devlog.md"'
close_round codex IN_PROGRESS "$D/.round-current@codex.md" 2>/dev/null
check "folded round keeps its number on merge" '[ "$(headings)" = "## Round 5,## Round 5 · codex," ]'

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
