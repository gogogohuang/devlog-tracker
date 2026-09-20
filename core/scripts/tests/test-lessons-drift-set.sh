#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/lessons-drift-set.sh" 5)"
[ "$OUT" = "NOT_STARTED" ] && echo "PASS: not started" || { echo "FAIL: $OUT"; FAIL=1; }

mkdir -p "$TMP/.devlog"
touch "$TMP/.devlog/.enabled"
OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/lessons-drift-set.sh" 5)"
[ "$OUT" = "LESSONS_NOT_ENABLED" ] && echo "PASS: lessons not enabled" || { echo "FAIL: $OUT"; FAIL=1; }

touch "$TMP/.devlog/.lessons-enabled"
printf '%s\n' '{"count": 2, "threshold": 3}' > "$TMP/.devlog/.lessons-advisory-state"

OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/lessons-drift-set.sh" 5)"
case "$OUT" in *LESSONS_DRIFT_THRESHOLD=5*) echo "PASS: set 5" ;; *) echo "FAIL: $OUT"; FAIL=1 ;; esac
grep -q '"count": 2' "$TMP/.devlog/.lessons-advisory-state" \
  && echo "PASS: count preserved" || { echo "FAIL: count reset"; FAIL=1; }
grep -q '"threshold": 5' "$TMP/.devlog/.lessons-advisory-state" \
  && echo "PASS: threshold written" || { echo "FAIL: threshold"; FAIL=1; }

CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/lessons-drift-set.sh" 0 >/dev/null 2>&1
[ $? -eq 1 ] && echo "PASS: reject 0" || { echo "FAIL: accepted 0"; FAIL=1; }

rm -f "$TMP/.devlog/.lessons-advisory-state"
OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/lessons-drift-set.sh" 7)"
case "$OUT" in *LESSONS_DRIFT_THRESHOLD=7*) echo "PASS: create 7" ;; *) echo "FAIL: create $OUT"; FAIL=1 ;; esac
grep -q '"count": 0' "$TMP/.devlog/.lessons-advisory-state" \
  && echo "PASS: create count 0" || { echo "FAIL: create count"; FAIL=1; }

# --- migrates an old .lessons-drift-state before applying the new threshold
rm -f "$TMP/.devlog/.lessons-advisory-state"
printf '%s\n' '{"mismatch_count": 4, "threshold": 3}' > "$TMP/.devlog/.lessons-drift-state"
OUT="$(CLAUDE_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/lessons-drift-set.sh" 9)"
case "$OUT" in *LESSONS_DRIFT_THRESHOLD=9*) echo "PASS: migrate then set 9" ;; *) echo "FAIL: $OUT"; FAIL=1 ;; esac
[ ! -f "$TMP/.devlog/.lessons-drift-state" ] && echo "PASS: old file removed after migrate+set" || { echo "FAIL: old file still present"; FAIL=1; }
grep -q '"count": 4' "$TMP/.devlog/.lessons-advisory-state" && echo "PASS: migrated count preserved through set" || { echo "FAIL: migrated count lost"; FAIL=1; }
grep -q '"threshold": 9' "$TMP/.devlog/.lessons-advisory-state" && echo "PASS: new threshold applied after migrate" || { echo "FAIL: threshold not applied"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
