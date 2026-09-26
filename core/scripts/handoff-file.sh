#!/usr/bin/env bash
# Sourced helper: write / clear the Session Handoff file. Content is the
# round's <session-handoff> block verbatim (docs/design/handoff-xml.md,
# docs/design/session-handoff-file.md).

_HANDOFF_FILE_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=handoff-fields.sh
. "$_HANDOFF_FILE_DIR/handoff-fields.sh"

# Prints the trimmed <session-handoff> block of Round blob $1; exit 1 when
# absent or invalid.
handoff_session_block() {
  local body
  body="$(handoff_section_of "$1" 'Session Handoff' | awk '
    { l[NR] = $0 } NF && !s { s = NR } NF { e = NR }
    END { for (i = s; s && i <= e; i++) print l[i] }
  ')"
  [ -n "$body" ] || return 1
  [ "$(handoff_format "$body")" = xml ] || return 1
  handoff_xml_check "$body" session-handoff >/dev/null || return 1
  printf '%s\n' "$body"
}

handoff_write() {
  local path="$1" blob="$2" dir tmp body
  body="$(handoff_session_block "$blob")" || return 1
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
