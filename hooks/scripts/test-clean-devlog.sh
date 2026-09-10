#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/devlog-md.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
assert_eq() {
  local d="$1" e="$2" a="$3"
  if [ "$e" = "$a" ]; then echo "PASS: $d"; else echo "FAIL: $d expected [$e] got [$a]"; FAIL=1; fi
}
perm_of() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}
make_round() {
  local file="$1" n="$2" status="$3"
  cat >> "$file" <<EOF
## Round $n — 2026-09-09T12:00:00+08:00

### Status
$status
EOF
}

# no --confirmed -> exit 1, nothing changes, no stdout
NOFLAG="$TMP/noflag"
mkdir -p "$NOFLAG/.devlog"
export CLAUDE_PROJECT_DIR="$NOFLAG"
printf '# project\n\n' > "$NOFLAG/.devlog/devlog.md"
make_round "$NOFLAG/.devlog/devlog.md" 1 DONE
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh" 2>/dev/null)"
assert_eq "no --confirmed: exit 1" 1 "$?"
assert_eq "no --confirmed: empty stdout" "" "$OUT"
grep -q '^## Round 1' "$NOFLAG/.devlog/devlog.md" && echo "PASS: no --confirmed leaves devlog.md untouched" || { echo "FAIL: devlog.md changed without --confirmed"; FAIL=1; }

# missing devlog.md -> exit 1, nothing created, no stdout
MISSING="$TMP/missing"
mkdir -p "$MISSING/.devlog"
export CLAUDE_PROJECT_DIR="$MISSING"
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed 2>/dev/null)"
assert_eq "missing log exit 1" 1 "$?"
assert_eq "missing log: empty stdout" "" "$OUT"
[ ! -e "$MISSING/.devlog/devlog.md" ] || { echo "FAIL: devlog.md created for missing case"; FAIL=1; }

# .round-open names a Round that isn't in the file -> refuse, don't touch anything
STALEOPEN="$TMP/staleopen"
mkdir -p "$STALEOPEN/.devlog"
export CLAUDE_PROJECT_DIR="$STALEOPEN"
printf '# project\n\n' > "$STALEOPEN/.devlog/devlog.md"
make_round "$STALEOPEN/.devlog/devlog.md" 1 DONE
make_round "$STALEOPEN/.devlog/devlog.md" 2 DONE
printf '%s\n' '{"round": 7, "opened_at": "now"}' > "$STALEOPEN/.devlog/.round-open"
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed 2>/dev/null)"
assert_eq "stale round-open: exit 1" 1 "$?"
assert_eq "stale round-open: empty stdout" "" "$OUT"
[ -f "$STALEOPEN/.devlog/devlog.md" ] && grep -q '^## Round 1' "$STALEOPEN/.devlog/devlog.md" && echo "PASS: stale round-open leaves devlog.md untouched" || { echo "FAIL: stale round-open touched devlog.md"; FAIL=1; }
grep -q '"round": 7' "$STALEOPEN/.devlog/.round-open" && echo "PASS: stale round-open file untouched" || { echo "FAIL: round-open file changed"; FAIL=1; }

# .round-open has an unparseable round while a real open Round exists -> refuse, don't touch anything
BADOPEN="$TMP/badopen"
mkdir -p "$BADOPEN/.devlog"
export CLAUDE_PROJECT_DIR="$BADOPEN"
printf '# project\n\n' > "$BADOPEN/.devlog/devlog.md"
make_round "$BADOPEN/.devlog/devlog.md" 1 IN_PROGRESS
printf '%s\n' '{"round": "abc", "opened_at": "now"}' > "$BADOPEN/.devlog/.round-open"
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed 2>/dev/null)"
assert_eq "unparseable round-open: exit 1" 1 "$?"
assert_eq "unparseable round-open: empty stdout" "" "$OUT"
grep -q '^## Round 1' "$BADOPEN/.devlog/devlog.md" && echo "PASS: unparseable round-open leaves the real open round in place" || { echo "FAIL: unparseable round-open deleted the open round"; FAIL=1; }

# open round: everything else discarded, this round renumbered to 1, body preserved verbatim
# (including a fenced fake heading, to prove the rename only touches the real heading line)
OPEN="$TMP/open"
mkdir -p "$OPEN/.devlog"
export CLAUDE_PROJECT_DIR="$OPEN"
printf '# project summary\n\nsome durable notes\n\n' > "$OPEN/.devlog/devlog.md"
make_round "$OPEN/.devlog/devlog.md" 1 DONE
make_round "$OPEN/.devlog/devlog.md" 2 DONE
{
  printf '## Round 3 — 2026-09-09T12:00:00+08:00\n\n'
  printf '### User Input\n```text\nplease do not touch this fake heading:\n## Round 1 fake\n## Round 99 — fake heading\n```\n\n'
  printf '### Status\nIN_PROGRESS\n'
} >> "$OPEN/.devlog/devlog.md"
printf '%s\n' '{"round": 3, "opened_at": "now"}' > "$OPEN/.devlog/.round-open"
printf '%s\n' '{"round": 2, "ticks": 1, "max_silent_ticks": 5}' > "$OPEN/.devlog/.span-open"
printf '%s\n' '{"rounds_since_checkpoint": 19, "max_silent_rounds": 20, "checkpoint_marker_count": 2}' > "$OPEN/.devlog/.checkpoint-state"
: > "$OPEN/.devlog/.interrupted"
: > "$OPEN/.devlog/.awaiting-reply"
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed)"
assert_eq "open round: exit 0" 0 "$?"
assert_eq "open round: stdout" "CLEANED KEPT_ROUND=1" "$OUT"
grep -q '^# project summary' "$OPEN/.devlog/devlog.md" && { echo "FAIL: project summary survived"; FAIL=1; } || echo "PASS: project summary discarded"
grep -q '^## Round 1 ' "$OPEN/.devlog/devlog.md" && echo "PASS: open round renumbered to 1" || { echo "FAIL: renumber"; FAIL=1; }
grep -q '^## Round 2 ' "$OPEN/.devlog/devlog.md" && { echo "FAIL: old round 2 survived"; FAIL=1; } || echo "PASS: old rounds gone"
[ "$(devlog_list_round_starts "$OPEN/.devlog/devlog.md" | wc -l | tr -d ' ')" = "1" ] && echo "PASS: exactly one real heading remains (fence-aware count)" || { echo "FAIL: heading count"; FAIL=1; }
grep -q '^please do not touch this fake heading:$' "$OPEN/.devlog/devlog.md" && echo "PASS: fenced body preserved verbatim" || { echo "FAIL: fenced body altered"; FAIL=1; }
grep -q '^## Round 1 fake$' "$OPEN/.devlog/devlog.md" && echo "PASS: fenced fake heading untouched" || { echo "FAIL: fenced fake heading renamed"; FAIL=1; }
grep -q '^## Round 99 — fake heading$' "$OPEN/.devlog/devlog.md" && echo "PASS: second fenced fake heading untouched" || { echo "FAIL: second fenced fake heading renamed"; FAIL=1; }
grep -q '"round": 1' "$OPEN/.devlog/.round-open" && echo "PASS: round-open reset to 1" || { echo "FAIL: round-open"; FAIL=1; }
[ ! -e "$OPEN/.devlog/.span-open" ] && echo "PASS: span-open removed" || { echo "FAIL: span-open remains"; FAIL=1; }
[ ! -e "$OPEN/.devlog/.interrupted" ] && echo "PASS: interrupted removed" || { echo "FAIL: interrupted remains"; FAIL=1; }
[ ! -e "$OPEN/.devlog/.awaiting-reply" ] && echo "PASS: awaiting-reply removed" || { echo "FAIL: awaiting-reply remains"; FAIL=1; }
grep -q '"rounds_since_checkpoint": 0' "$OPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint rounds reset" || { echo "FAIL: checkpoint rounds"; FAIL=1; }
grep -q '"checkpoint_marker_count": 0' "$OPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint marker count reset" || { echo "FAIL: checkpoint marker count"; FAIL=1; }
grep -q '"max_silent_rounds": 20' "$OPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint max kept" || { echo "FAIL: checkpoint max"; FAIL=1; }
PERM="$(perm_of "$OPEN/.devlog/devlog.md")"
[ "$PERM" != "600" ] && echo "PASS: rewritten devlog.md is not owner-only (mode $PERM)" || { echo "FAIL: rewritten devlog.md is 600"; FAIL=1; }

# no open round (never started / paused): whole file deleted
NOOPEN="$TMP/noopen"
mkdir -p "$NOOPEN/.devlog"
export CLAUDE_PROJECT_DIR="$NOOPEN"
printf '# project summary\n\n' > "$NOOPEN/.devlog/devlog.md"
make_round "$NOOPEN/.devlog/devlog.md" 1 DONE
make_round "$NOOPEN/.devlog/devlog.md" 2 DONE
printf '%s\n' '{"rounds_since_checkpoint": 5, "max_silent_rounds": 20, "checkpoint_marker_count": 1}' > "$NOOPEN/.devlog/.checkpoint-state"
printf '%s\n' '# archive' > "$NOOPEN/.devlog/devlog.archive.md"
printf '%s\n' '# kept' > "$NOOPEN/.devlog/devlog.span-mode.md"
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed)"
assert_eq "no open round: exit 0" 0 "$?"
assert_eq "no open round: stdout" "CLEANED KEPT_ROUND=0" "$OUT"
[ ! -e "$NOOPEN/.devlog/devlog.md" ] && echo "PASS: devlog.md deleted" || { echo "FAIL: devlog.md remains"; FAIL=1; }
grep -q '"rounds_since_checkpoint": 0' "$NOOPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint rounds reset (no-open)" || { echo "FAIL: checkpoint rounds (no-open)"; FAIL=1; }
grep -q '"checkpoint_marker_count": 0' "$NOOPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint marker count reset (no-open)" || { echo "FAIL: checkpoint marker count (no-open)"; FAIL=1; }
grep -q '^# archive' "$NOOPEN/.devlog/devlog.archive.md" && echo "PASS: archive.md untouched (no-open)" || { echo "FAIL: archive.md touched (no-open)"; FAIL=1; }
grep -q '^# kept' "$NOOPEN/.devlog/devlog.span-mode.md" && echo "PASS: named keep file untouched (no-open)" || { echo "FAIL: named keep file touched (no-open)"; FAIL=1; }

# does not touch archive.md or named keep files (open-round branch)
SIB="$TMP/siblings"
mkdir -p "$SIB/.devlog"
export CLAUDE_PROJECT_DIR="$SIB"
printf '%s\n' '# archive' > "$SIB/.devlog/devlog.archive.md"
printf '%s\n' '# kept' > "$SIB/.devlog/devlog.span-mode.md"
printf '# project\n\n' > "$SIB/.devlog/devlog.md"
make_round "$SIB/.devlog/devlog.md" 1 DONE
printf '%s\n' '{"round": 1, "opened_at": "now"}' > "$SIB/.devlog/.round-open"
bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed >/dev/null
grep -q '^# archive' "$SIB/.devlog/devlog.archive.md" && echo "PASS: archive.md untouched" || { echo "FAIL: archive.md touched"; FAIL=1; }
grep -q '^# kept' "$SIB/.devlog/devlog.span-mode.md" && echo "PASS: named keep file untouched" || { echo "FAIL: named keep file touched"; FAIL=1; }

# .enabled is never touched either way
ENAB="$TMP/enabled"
mkdir -p "$ENAB/.devlog"
export CLAUDE_PROJECT_DIR="$ENAB"
printf '%s\n' 'enabled' > "$ENAB/.devlog/.enabled"
printf '# project\n\n' > "$ENAB/.devlog/devlog.md"
make_round "$ENAB/.devlog/devlog.md" 1 IN_PROGRESS
printf '%s\n' '{"round": 1, "opened_at": "now"}' > "$ENAB/.devlog/.round-open"
bash "$SCRIPT_DIR/clean-devlog.sh" --confirmed >/dev/null
[ -f "$ENAB/.devlog/.enabled" ] && echo "PASS: .enabled untouched" || { echo "FAIL: .enabled removed"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
