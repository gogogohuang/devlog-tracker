#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Acquire writes its own pid into the lock dir; release removes the whole
# dir (pid file included), not just an empty rmdir.
devlog_lock_acquire
[ -f "$DEVLOG_DIR/.lock/pid" ] && [ "$(cat "$DEVLOG_DIR/.lock/pid")" = "$$" ] \
  && echo "PASS: acquire writes own pid" || { echo "FAIL: pid file missing/wrong"; FAIL=1; }
devlog_lock_release
[ ! -d "$DEVLOG_DIR/.lock" ] && echo "PASS: release removes dir incl. pid file" \
  || { echo "FAIL: lock dir survives release"; FAIL=1; }

# Stale lock (pid file names a process that is no longer running): reclaimed
# near-instantly instead of waiting out the full contention timeout.
mkdir "$DEVLOG_DIR/.lock"
echo 999999 > "$DEVLOG_DIR/.lock/pid"
START="$(date +%s)"
devlog_lock_acquire
END="$(date +%s)"
ELAPSED=$((END - START))
[ "${LOCK_HELD:-0}" -eq 1 ] && [ "$ELAPSED" -le 1 ] \
  && echo "PASS: stale lock reclaimed fast" || { echo "FAIL: stale reclaim held=$LOCK_HELD elapsed=$ELAPSED"; FAIL=1; }
devlog_lock_release

# Live contention (pid file names a still-running process): fails open after
# the timeout as before, but now reports who is holding it.
sleep 5 &
LIVE_PID=$!
mkdir "$DEVLOG_DIR/.lock"
echo "$LIVE_PID" > "$DEVLOG_DIR/.lock/pid"
START="$(date +%s)"
devlog_lock_acquire
END="$(date +%s)"
ELAPSED=$((END - START))
[ "${LOCK_HELD:-0}" -eq 0 ] && [ "$ELAPSED" -ge 2 ] && [ "$ELAPSED" -le 3 ] \
  && [ "${LOCK_CONTENDED_BY:-}" = "$LIVE_PID" ] \
  && echo "PASS: live contention reports holder pid" \
  || { echo "FAIL: live contention held=$LOCK_HELD elapsed=$ELAPSED by=${LOCK_CONTENDED_BY:-}"; FAIL=1; }
kill "$LIVE_PID" 2>/dev/null || true
wait "$LIVE_PID" 2>/dev/null || true
rm -rf "$DEVLOG_DIR/.lock"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
