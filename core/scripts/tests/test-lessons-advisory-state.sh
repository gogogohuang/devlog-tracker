#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lessons-advisory-state.sh
. "$SCRIPT_DIR/lessons-advisory-state.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAIL=0

# --- migrate: neither file present -> no-op --------------------------------
lessons_advisory_migrate "$TMP_ROOT"
if [ ! -f "$TMP_ROOT/.lessons-advisory-state" ] && [ ! -f "$TMP_ROOT/.lessons-drift-state" ]; then
  echo "PASS: migrate no-op when neither file exists"
else
  echo "FAIL: migrate created a file when neither existed"; FAIL=1
fi

# --- migrate: old exists, new doesn't -> migrates and removes old ----------
printf '%s\n' '{"mismatch_count": 2, "threshold": 5}' > "$TMP_ROOT/.lessons-drift-state"
lessons_advisory_migrate "$TMP_ROOT"
if [ -f "$TMP_ROOT/.lessons-advisory-state" ]; then echo "PASS: migrate creates new file"; else echo "FAIL: new file missing after migrate"; FAIL=1; fi
grep -q '"count": 2' "$TMP_ROOT/.lessons-advisory-state" && echo "PASS: migrate preserves count" || { echo "FAIL: count not migrated"; FAIL=1; }
grep -q '"threshold": 5' "$TMP_ROOT/.lessons-advisory-state" && echo "PASS: migrate preserves threshold" || { echo "FAIL: threshold not migrated"; FAIL=1; }
if [ ! -f "$TMP_ROOT/.lessons-drift-state" ]; then echo "PASS: migrate removes old file"; else echo "FAIL: old file still present after migrate"; FAIL=1; fi

# --- migrate: new already exists -> leaves it alone, doesn't touch old -----
rm -f "$TMP_ROOT/.lessons-advisory-state" "$TMP_ROOT/.lessons-drift-state"
printf '%s\n' '{"count": 9, "threshold": 9}' > "$TMP_ROOT/.lessons-advisory-state"
printf '%s\n' '{"mismatch_count": 1, "threshold": 1}' > "$TMP_ROOT/.lessons-drift-state"
lessons_advisory_migrate "$TMP_ROOT"
grep -q '"count": 9' "$TMP_ROOT/.lessons-advisory-state" && echo "PASS: migrate leaves existing new file untouched" || { echo "FAIL: existing new file was overwritten"; FAIL=1; }

# --- migrate: idempotent (second call after migration is a no-op) ----------
rm -f "$TMP_ROOT/.lessons-advisory-state" "$TMP_ROOT/.lessons-drift-state"
printf '%s\n' '{"mismatch_count": 1, "threshold": 3}' > "$TMP_ROOT/.lessons-drift-state"
lessons_advisory_migrate "$TMP_ROOT"
lessons_advisory_migrate "$TMP_ROOT"
grep -q '"count": 1' "$TMP_ROOT/.lessons-advisory-state" && echo "PASS: second migrate call is a no-op" || { echo "FAIL: second migrate call changed state"; FAIL=1; }

# --- bump: creates file with defaults, increments, no print below threshold
rm -f "$TMP_ROOT/.lessons-advisory-state"
OUT="$(lessons_advisory_bump "$TMP_ROOT/.lessons-advisory-state")"
[ -z "$OUT" ] && echo "PASS: bump 1/3 prints nothing" || { echo "FAIL: bump 1/3 printed [$OUT]"; FAIL=1; }
grep -q '"count": 1' "$TMP_ROOT/.lessons-advisory-state" && echo "PASS: bump creates file with count=1" || { echo "FAIL: bump did not create count=1"; FAIL=1; }
grep -q '"threshold": 3' "$TMP_ROOT/.lessons-advisory-state" && echo "PASS: bump defaults threshold to 3" || { echo "FAIL: bump did not default threshold"; FAIL=1; }

# --- bump: reaching threshold prints and resets -----------------------------
OUT="$(lessons_advisory_bump "$TMP_ROOT/.lessons-advisory-state")"
[ -z "$OUT" ] && echo "PASS: bump 2/3 prints nothing" || { echo "FAIL: bump 2/3 printed [$OUT]"; FAIL=1; }
OUT="$(lessons_advisory_bump "$TMP_ROOT/.lessons-advisory-state")"
case "$OUT" in *"[Lessons Mode 提示]"*) echo "PASS: bump 3/3 prints the advisory" ;; *) echo "FAIL: bump 3/3 did not print, got [$OUT]"; FAIL=1 ;; esac
grep -q '"count": 0' "$TMP_ROOT/.lessons-advisory-state" && echo "PASS: bump resets count to 0 after printing" || { echo "FAIL: count not reset"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
