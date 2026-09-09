#!/usr/bin/env bash
# Sourced helper for serializing writes under .devlog.
devlog_lock_acquire() {
  local dir="${DEVLOG_DIR:-.}/.lock"
  local start now
  start="$(date +%s 2>/dev/null || echo 0)"
  LOCK_HELD=0
  while true; do
    if mkdir "$dir" 2>/dev/null; then
      LOCK_HELD=1
      return 0
    fi
    now="$(date +%s 2>/dev/null || echo 0)"
    if [ $((now - start)) -ge 2 ]; then
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
}

devlog_lock_release() {
  if [ "${LOCK_HELD:-0}" -eq 1 ]; then
    rmdir "${DEVLOG_DIR:-.}/.lock" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

devlog_with_lock() {
  devlog_lock_acquire
  "$@"
  local result=$?
  devlog_lock_release
  return "$result"
}
