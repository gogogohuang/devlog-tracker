#!/usr/bin/env bash
# Sourced helper: validate / extract / write / clear Session Handoff file.
# See docs/design/session-handoff-file.md.

# Odd ``` count → treat as no fence (same fail-open as enforce-devlog.sh).
_handoff_nofence_flag() {
  local blob="$1" n
  n="$(printf '%s\n' "$blob" | grep -c '^[ \t]*```' 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ $((n % 2)) -eq 1 ]; then
    echo 1
  else
    echo 0
  fi
}

# Returns 0 if $1 (a Round blob) has ### Session Handoff with #### 決策 /
# #### 待解問題 / #### 失敗嘗試 in that order, each with a non-empty body.
handoff_session_section_ok() {
  local blob="$1" nofence
  nofence="$(_handoff_nofence_flag "$blob")"
  printf '%s\n' "$blob" | awk -v nofence="$nofence" '
    BEGIN { ok = 0 }
    /^[ \t]*```/ { if (!nofence) fence = !fence; next }
    fence { next }
    /^### Session Handoff[ \t]*$/ { in_sh = 1; next }
    in_sh && /^### / { exit }
    in_sh && /^## / { exit }
    in_sh && /^#### / {
      name = $0
      sub(/^#### [ \t]*/, "", name)
      sub(/[ \t]+$/, "", name)
      if (name == "決策" || name == "待解問題" || name == "失敗嘗試") {
        if (expecting_body) { exit }
        if (name == "決策") {
          if (seen_decision || seen_open || seen_failed) exit
          seen_decision = 1
          expecting_body = 1
        } else if (name == "待解問題") {
          if (!seen_decision || seen_open || seen_failed) exit
          seen_open = 1
          expecting_body = 1
        } else {
          if (!seen_decision || !seen_open || seen_failed) exit
          seen_failed = 1
          expecting_body = 1
        }
      }
      next
    }
    in_sh && expecting_body {
      if ($0 ~ /[^[:space:]]/) {
        expecting_body = 0
        if (seen_decision && seen_open && seen_failed) ok = 1
      }
      next
    }
    END { exit(ok && seen_decision && seen_open && seen_failed && !expecting_body ? 0 : 1) }
  '
}

# Print independent-file markdown from Round blob $1. Exit 1 if invalid.
handoff_extract_file_body() {
  local blob="$1" nofence
  handoff_session_section_ok "$blob" || return 1
  nofence="$(_handoff_nofence_flag "$blob")"
  printf '%s\n' "$blob" | awk -v nofence="$nofence" '
    BEGIN { print "## Session Handoff"; print "" }
    /^[ \t]*```/ { if (!nofence) fence = !fence; next }
    fence { next }
    /^### Session Handoff[ \t]*$/ { in_sh = 1; next }
    in_sh && /^### / { exit }
    in_sh && /^## / { exit }
    in_sh && /^#### / {
      name = $0
      sub(/^#### [ \t]*/, "", name)
      sub(/[ \t]+$/, "", name)
      if (name == "決策" || name == "待解問題" || name == "失敗嘗試") {
        if (printing) print ""
        print "### " name
        printing = 1
        grab = 1
        next
      }
      grab = 0
      next
    }
    in_sh && grab { print }
  '
}

# Atomic write of extracted body to $1 from Round blob $2.
handoff_write() {
  local path="$1" blob="$2" dir tmp body
  body="$(handoff_extract_file_body "$blob")" || return 1
  dir="$(dirname "$path")"
  mkdir -p "$dir" 2>/dev/null || true
  tmp="$(mktemp "$dir/.handoff.XXXXXX")" || return 1
  printf '%s\n' "$body" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$path" || { rm -f "$tmp"; return 1; }
  return 0
}

handoff_clear() {
  rm -f "$1"
}
