#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/devlog-lock.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DEVLOG_DIR="$TMP/.devlog"
mkdir -p "$DEVLOG_DIR"
FAIL=0

devlog_lock_acquire
[ "${LOCK_HELD:-0}" -eq 1 ] && [ -d "$DEVLOG_DIR/.lock" ] \
  && echo "PASS: acquired" || { echo "FAIL: acquire"; FAIL=1; }
mkdir "$DEVLOG_DIR/.lock" >/dev/null 2>&1
[ "$?" -ne 0 ] && echo "PASS: second mkdir excluded" || { echo "FAIL: duplicate mkdir"; FAIL=1; }
devlog_lock_release
devlog_lock_acquire
[ "${LOCK_HELD:-0}" -eq 1 ] && echo "PASS: reacquired after release" || { echo "FAIL: reacquire"; FAIL=1; }
devlog_lock_release

mkdir "$DEVLOG_DIR/.lock"
START="$(date +%s)"
devlog_lock_acquire
END="$(date +%s)"
ELAPSED=$((END - START))
[ "${LOCK_HELD:-0}" -eq 0 ] && [ "$ELAPSED" -ge 2 ] && [ "$ELAPSED" -le 3 ] \
  && echo "PASS: contention fails open" || { echo "FAIL: contention held=$LOCK_HELD elapsed=$ELAPSED"; FAIL=1; }
rmdir "$DEVLOG_DIR/.lock"

MIN_PATH="$TMP/min-path"
mkdir "$MIN_PATH"
ln -s "$(command -v bash)" "$MIN_PATH/bash"
HELD="$(PATH="$MIN_PATH" bash -c '. "$1"; DEVLOG_DIR="$2"; devlog_lock_acquire; echo "${LOCK_HELD:-0}"' _ "$SCRIPT_DIR/devlog-lock.sh" "$DEVLOG_DIR")"
[ "$HELD" = "0" ] && echo "PASS: missing lock tools fails open" || { echo "FAIL: restricted path held=$HELD"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
