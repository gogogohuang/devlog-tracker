#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
assert_eq() {
  local d="$1" e="$2" a="$3"
  if [ "$e" = "$a" ]; then echo "PASS: $d"; else echo "FAIL: $d expected [$e] got [$a]"; FAIL=1; fi
}
make_round() {
  local file="$1" n="$2" status="$3"
  cat >> "$file" <<EOF
## Round $n — 2026-09-09T12:00:00+08:00

### Status
$status
EOF
}

# missing devlog.md -> exit 1, nothing created
MISSING="$TMP/missing"
mkdir -p "$MISSING/.devlog"
export CLAUDE_PROJECT_DIR="$MISSING"
bash "$SCRIPT_DIR/clean-devlog.sh" >/dev/null 2>&1
assert_eq "missing log exit 1" 1 "$?"
[ ! -e "$MISSING/.devlog/devlog.md" ] || { echo "FAIL: devlog.md created for missing case"; FAIL=1; }

# open round: everything else discarded, this round renumbered to 1
OPEN="$TMP/open"
mkdir -p "$OPEN/.devlog"
export CLAUDE_PROJECT_DIR="$OPEN"
printf '# project summary\n\nsome durable notes\n\n' > "$OPEN/.devlog/devlog.md"
make_round "$OPEN/.devlog/devlog.md" 1 DONE
make_round "$OPEN/.devlog/devlog.md" 2 DONE
make_round "$OPEN/.devlog/devlog.md" 3 IN_PROGRESS
printf '%s\n' '{"round": 3, "opened_at": "now"}' > "$OPEN/.devlog/.round-open"
printf '%s\n' '{"round": 2, "ticks": 1, "max_silent_ticks": 5}' > "$OPEN/.devlog/.span-open"
printf '%s\n' '{"rounds_since_checkpoint": 19, "max_silent_rounds": 20, "checkpoint_marker_count": 2}' > "$OPEN/.devlog/.checkpoint-state"
: > "$OPEN/.devlog/.interrupted"
: > "$OPEN/.devlog/.awaiting-reply"
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh")"
assert_eq "open round: exit 0" 0 "$?"
assert_eq "open round: stdout" "CLEANED KEPT_ROUND=1" "$OUT"
grep -q '^# project summary' "$OPEN/.devlog/devlog.md" && { echo "FAIL: project summary survived"; FAIL=1; } || echo "PASS: project summary discarded"
grep -q '^## Round 1 ' "$OPEN/.devlog/devlog.md" && echo "PASS: open round renumbered to 1" || { echo "FAIL: renumber"; FAIL=1; }
grep -q '^## Round 2' "$OPEN/.devlog/devlog.md" && { echo "FAIL: old round 2 survived"; FAIL=1; } || echo "PASS: old rounds gone"
[ "$(grep -c '^## Round' "$OPEN/.devlog/devlog.md")" = "1" ] && echo "PASS: exactly one round remains" || { echo "FAIL: round count"; FAIL=1; }
grep -q '"round": 1' "$OPEN/.devlog/.round-open" && echo "PASS: round-open reset to 1" || { echo "FAIL: round-open"; FAIL=1; }
[ ! -e "$OPEN/.devlog/.span-open" ] && echo "PASS: span-open removed" || { echo "FAIL: span-open remains"; FAIL=1; }
[ ! -e "$OPEN/.devlog/.interrupted" ] && echo "PASS: interrupted removed" || { echo "FAIL: interrupted remains"; FAIL=1; }
[ ! -e "$OPEN/.devlog/.awaiting-reply" ] && echo "PASS: awaiting-reply removed" || { echo "FAIL: awaiting-reply remains"; FAIL=1; }
grep -q '"rounds_since_checkpoint": 0' "$OPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint rounds reset" || { echo "FAIL: checkpoint rounds"; FAIL=1; }
grep -q '"checkpoint_marker_count": 0' "$OPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint marker count reset" || { echo "FAIL: checkpoint marker count"; FAIL=1; }
grep -q '"max_silent_rounds": 20' "$OPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint max kept" || { echo "FAIL: checkpoint max"; FAIL=1; }

# no open round (never started / paused): whole file deleted
NOOPEN="$TMP/noopen"
mkdir -p "$NOOPEN/.devlog"
export CLAUDE_PROJECT_DIR="$NOOPEN"
printf '# project summary\n\n' > "$NOOPEN/.devlog/devlog.md"
make_round "$NOOPEN/.devlog/devlog.md" 1 DONE
make_round "$NOOPEN/.devlog/devlog.md" 2 DONE
printf '%s\n' '{"rounds_since_checkpoint": 5, "max_silent_rounds": 20, "checkpoint_marker_count": 1}' > "$NOOPEN/.devlog/.checkpoint-state"
OUT="$(bash "$SCRIPT_DIR/clean-devlog.sh")"
assert_eq "no open round: exit 0" 0 "$?"
assert_eq "no open round: stdout" "CLEANED KEPT_ROUND=0" "$OUT"
[ ! -e "$NOOPEN/.devlog/devlog.md" ] && echo "PASS: devlog.md deleted" || { echo "FAIL: devlog.md remains"; FAIL=1; }
grep -q '"rounds_since_checkpoint": 0' "$NOOPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint rounds reset (no-open)" || { echo "FAIL: checkpoint rounds (no-open)"; FAIL=1; }
grep -q '"checkpoint_marker_count": 0' "$NOOPEN/.devlog/.checkpoint-state" && echo "PASS: checkpoint marker count reset (no-open)" || { echo "FAIL: checkpoint marker count (no-open)"; FAIL=1; }

# does not touch archive.md or named keep files
SIB="$TMP/siblings"
mkdir -p "$SIB/.devlog"
export CLAUDE_PROJECT_DIR="$SIB"
printf '%s\n' '# archive' > "$SIB/.devlog/devlog.archive.md"
printf '%s\n' '# kept' > "$SIB/.devlog/devlog.span-mode.md"
printf '# project\n\n' > "$SIB/.devlog/devlog.md"
make_round "$SIB/.devlog/devlog.md" 1 DONE
printf '%s\n' '{"round": 1, "opened_at": "now"}' > "$SIB/.devlog/.round-open"
bash "$SCRIPT_DIR/clean-devlog.sh" >/dev/null
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
bash "$SCRIPT_DIR/clean-devlog.sh" >/dev/null
[ -f "$ENAB/.devlog/.enabled" ] && echo "PASS: .enabled untouched" || { echo "FAIL: .enabled removed"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
