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

export CLAUDE_PROJECT_DIR="$TMP/missing"
bash "$SCRIPT_DIR/keep-move.sh" --from 1 --to 1 --name x >/dev/null 2>&1
assert_eq "missing log exit 1" 1 "$?"

BAD="$TMP/bad-name"
mkdir -p "$BAD/.devlog"
export CLAUDE_PROJECT_DIR="$BAD"
make_round "$BAD/.devlog/devlog.md" 1 DONE
bash "$SCRIPT_DIR/keep-move.sh" --from 1 --to 1 --name devlog.md >/dev/null 2>&1
assert_eq "devlog.md name rejected" 1 "$?"
[ ! -e "$BAD/.devlog/devlog.md.md" ] || { echo "FAIL: devlog.md.md created"; FAIL=1; }

EP="$TMP/episode"
mkdir -p "$EP/.devlog"
export CLAUDE_PROJECT_DIR="$EP"
printf '# project\n\n' > "$EP/.devlog/devlog.md"
make_round "$EP/.devlog/devlog.md" 1 DONE
make_round "$EP/.devlog/devlog.md" 2 DONE
make_round "$EP/.devlog/devlog.md" 3 IN_PROGRESS
printf '%s\n' '{"round": 3, "opened_at": "now"}' > "$EP/.devlog/.round-open"
bash "$SCRIPT_DIR/keep-move.sh" --from 1 --to 1 --name first >/dev/null
assert_eq "episode keep exits 0" 0 "$?"
grep -q '^# Kept log' "$EP/.devlog/devlog.first.md" && echo "PASS: provenance written" || { echo "FAIL: provenance"; FAIL=1; }
grep -q '^## Round 1' "$EP/.devlog/devlog.first.md" && echo "PASS: named file has round" || { echo "FAIL: named round"; FAIL=1; }
grep -q '^## Round 1' "$EP/.devlog/devlog.md" && { echo "FAIL: moved round remains"; FAIL=1; } || echo "PASS: moved round removed"
grep -q '^## Round 3' "$EP/.devlog/devlog.md" && echo "PASS: open round remains" || { echo "FAIL: open moved"; FAIL=1; }
bash "$SCRIPT_DIR/keep-move.sh" --from 3 --to 3 --name open >/dev/null 2>&1
assert_eq "open round rejected" 1 "$?"
bash "$SCRIPT_DIR/keep-move.sh" --from 2 --to 2 --name first >/dev/null 2>&1
assert_eq "overwrite rejected" 1 "$?"

FULL="$TMP/full"
mkdir -p "$FULL/.devlog"
export CLAUDE_PROJECT_DIR="$FULL"
printf '# project\n\n' > "$FULL/.devlog/devlog.md"
make_round "$FULL/.devlog/devlog.md" 1 DONE
make_round "$FULL/.devlog/devlog.md" 2 DONE
make_round "$FULL/.devlog/devlog.md" 3 IN_PROGRESS
printf '%s\n' '{"round": 3, "opened_at": "now"}' > "$FULL/.devlog/.round-open"
printf '%s\n' '{"round": 2, "ticks": 1, "max_silent_ticks": 5}' > "$FULL/.devlog/.span-open"
printf '%s\n' '{"rounds_since_checkpoint": 19, "max_silent_rounds": 20, "checkpoint_marker_count": 0}' > "$FULL/.devlog/.checkpoint-state"
bash "$SCRIPT_DIR/keep-move.sh" --from 1 --to 2 --name episode >/dev/null
assert_eq "full keep exits 0" 0 "$?"
grep -q '^## Round 1 ' "$FULL/.devlog/devlog.md" && echo "PASS: open round renumbered" || { echo "FAIL: full renumber"; FAIL=1; }
grep -q '"round": 1' "$FULL/.devlog/.round-open" && echo "PASS: round state reset" || { echo "FAIL: round state"; FAIL=1; }
grep -q '"rounds_since_checkpoint": 0' "$FULL/.devlog/.checkpoint-state" && echo "PASS: checkpoint reset" || { echo "FAIL: checkpoint state"; FAIL=1; }
grep -q '"max_silent_rounds": 20' "$FULL/.devlog/.checkpoint-state" && echo "PASS: checkpoint max kept" || { echo "FAIL: checkpoint max"; FAIL=1; }
[ ! -e "$FULL/.devlog/.span-open" ] && echo "PASS: span removed" || { echo "FAIL: span remains"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
