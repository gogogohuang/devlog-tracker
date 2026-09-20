# shellcheck shell=bash
# Sourced by round-start.sh / lessons-on.sh / lessons-drift-set.sh. Owns the shared
# `.lessons-advisory-state` file (docs/design/lessons-mode.md 「機制性訊號：
# 共用計數器」): a `count`/`threshold` pair fed by more than one mechanical
# signal (workspace drift, accumulated BLOCKED rounds), so the file and
# function names are signal-agnostic rather than "drift"-specific.
_lessons_advisory_state_src="${BASH_SOURCE[0]}"
_LESSONS_ADVISORY_STATE_DIR="$(cd "${_lessons_advisory_state_src%/*}" && pwd)"
# shellcheck source=json-field.sh
. "$_LESSONS_ADVISORY_STATE_DIR/json-field.sh"

# One-time migration from the old, drift-only file name/fields. No-op unless
# the old file exists and the new one doesn't; safe to call on every
# invocation (idempotent, cheap after the first migration).
lessons_advisory_migrate() {
  local devlog_dir="$1"
  local old="$devlog_dir/.lessons-drift-state"
  local new="$devlog_dir/.lessons-advisory-state"
  [ -f "$new" ] && return 0
  [ -f "$old" ] || return 0
  local count threshold
  count="$(json_int_get "$old" mismatch_count)"
  threshold="$(json_int_get "$old" threshold)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  case "$threshold" in ''|*[!0-9]*) threshold=3 ;; esac
  printf '{"count": %s, "threshold": %s}\n' "$count" "$threshold" > "$new" 2>/dev/null || return 0
  rm -f "$old" 2>/dev/null || true
}

# Increments $1 (the advisory-state file, created with defaults if missing),
# printing the shared advisory line and resetting to 0 once the threshold is
# reached. Callers call this once per mechanical signal occurrence; a
# printed line means "surface this to Claude" (round-start.sh's stdout is
# the only place a non-blocking hook message reaches Claude's context).
lessons_advisory_bump() {
  local file="$1" count max newcount
  if [ ! -f "$file" ]; then
    printf '%s\n' '{"count": 0, "threshold": 3}' > "$file" 2>/dev/null || true
  fi
  count="$(json_int_get "$file" count)"
  max="$(json_int_get "$file" threshold)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  case "$max" in ''|*[!0-9]*) max=3 ;; esac
  newcount=$((count + 1))
  if [ "$newcount" -ge "$max" ]; then
    json_int_set "$file" count 0
    printf '\n[Lessons Mode 提示] 流程訊號已累積出現 %s 次（門檻 %s）。可考慮用 lessons-append.sh 記一筆流程教訓，非強制。\n' "$newcount" "$max"
  else
    json_int_set "$file" count "$newcount"
  fi
}
