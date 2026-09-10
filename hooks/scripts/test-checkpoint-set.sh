#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/checkpoint-set.sh" 25)"
[ "$OUT" = "NOT_STARTED" ] && echo "PASS: not started" || { echo "FAIL: $OUT"; FAIL=1; }

mkdir -p "$TMP/.devlog"
touch "$TMP/.devlog/.enabled"
printf '%s\n' '{"rounds_since_checkpoint": 7, "max_silent_rounds": 20, "checkpoint_marker_count": 2}' \
  > "$TMP/.devlog/.checkpoint-state"

OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/checkpoint-set.sh" 30)"
case "$OUT" in *CHECKPOINT_MAX_SILENT_ROUNDS=30*) echo "PASS: set 30" ;; *) echo "FAIL: $OUT"; FAIL=1 ;; esac
grep -q '"rounds_since_checkpoint": 7' "$TMP/.devlog/.checkpoint-state" \
  && echo "PASS: rounds preserved" || { echo "FAIL: rounds reset"; FAIL=1; }
grep -q '"checkpoint_marker_count": 2' "$TMP/.devlog/.checkpoint-state" \
  && echo "PASS: markers preserved" || { echo "FAIL: markers reset"; FAIL=1; }
grep -q '"max_silent_rounds": 30' "$TMP/.devlog/.checkpoint-state" \
  && echo "PASS: max written" || { echo "FAIL: max"; FAIL=1; }

CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/checkpoint-set.sh" 0 >/dev/null 2>&1
[ $? -eq 1 ] && echo "PASS: reject 0" || { echo "FAIL: accepted 0"; FAIL=1; }

# create when missing
rm -f "$TMP/.devlog/.checkpoint-state"
OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/checkpoint-set.sh" 15)"
case "$OUT" in *CHECKPOINT_MAX_SILENT_ROUNDS=15*) echo "PASS: create 15" ;; *) echo "FAIL: create $OUT"; FAIL=1 ;; esac
grep -q '"rounds_since_checkpoint": 0' "$TMP/.devlog/.checkpoint-state" \
  && echo "PASS: create rounds 0" || { echo "FAIL: create rounds"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
