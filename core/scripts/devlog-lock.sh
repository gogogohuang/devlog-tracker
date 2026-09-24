#!/usr/bin/env bash
# Sourced helper for serializing writes under .devlog.
#
# The holder exports DEVLOG_LOCK_OWNER=<its pid>, so a script it runs as a
# child (round-start.sh -> close-open-round.sh) finds the lock already its
# own and proceeds instead of waiting out the contention timeout on its
# parent. The child never holds it, so its release leaves the lock alone.
devlog_lock_acquire() {
  local dir="${DEVLOG_DIR:-.}/.lock"
  local start now pid
  LOCK_HELD=0
  LOCK_CONTENDED_BY=""
  command -v mkdir >/dev/null 2>&1 || return 0
  command -v rmdir >/dev/null 2>&1 || return 0
  command -v date >/dev/null 2>&1 || return 0
  command -v sleep >/dev/null 2>&1 || return 0
  start="$(date +%s 2>/dev/null || echo 0)"
  while true; do
    if mkdir "$dir" 2>/dev/null; then
      LOCK_HELD=1
      printf '%s\n' "$$" > "$dir/pid" 2>/dev/null || true
      export DEVLOG_LOCK_OWNER="$$"
      return 0
    fi
    pid="$(cat "$dir/pid" 2>/dev/null || true)"
    case "$pid" in
      ''|*[!0-9]*) pid='' ;;
    esac
    if [ -n "$pid" ] && [ "$pid" = "${DEVLOG_LOCK_OWNER:-}" ]; then
      return 0
    fi
    # Stale lock: the pid that created it is no longer running (a crashed
    # session), so reclaim it immediately instead of waiting out the full
    # contention timeout below.
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$dir" 2>/dev/null || true
      continue
    fi
    now="$(date +%s 2>/dev/null || echo 0)"
    if [ $((now - start)) -ge 2 ]; then
      # shellcheck disable=SC2034 # consumed by callers (e.g. enforce-devlog.sh), not used in this file
      LOCK_CONTENDED_BY="$pid"
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
}

devlog_lock_release() {
  if [ "${LOCK_HELD:-0}" -eq 1 ]; then
    rm -f "${DEVLOG_DIR:-.}/.lock/pid" 2>/dev/null || true
    rmdir "${DEVLOG_DIR:-.}/.lock" 2>/dev/null || true
    LOCK_HELD=0
    unset DEVLOG_LOCK_OWNER
  fi
}

devlog_with_lock() {
  devlog_lock_acquire
  "$@"
  local result=$?
  devlog_lock_release
  return "$result"
}
