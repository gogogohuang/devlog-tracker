#!/usr/bin/env bash
# Writes rules chosen in /devlog-tracker:promote into the managed block
# <!-- devlog-tracker:rules:begin/end --> of <target>
# (docs/design/read-side-and-promote.md D). Append-only: never edits or
# removes a rule already in the block, never touches anything outside it.
# Exact-line duplicates (against the block, and within the input) are skipped.
# Usage: promote-write.sh <target> <rules-file>
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

TARGET="${1:-}"
RULES="${2:-}"
if [ -z "$TARGET" ] || [ ! -f "$RULES" ]; then
  echo "USAGE: promote-write.sh <target> <rules-file>" >&2
  exit 2
fi
BEGIN_MARK='<!-- devlog-tracker:rules:begin -->'
END_MARK='<!-- devlog-tracker:rules:end -->'

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
NEW="$(mktemp "${TMPDIR:-/tmp}/devlog-promote.XXXXXX")" || exit 1
EXISTING="$(mktemp "${TMPDIR:-/tmp}/devlog-promote.XXXXXX")" || exit 1
TO_ADD="$(mktemp "${TMPDIR:-/tmp}/devlog-promote.XXXXXX")" || exit 1
trap 'rm -f "$NEW" "$EXISTING" "$TO_ADD" "$TARGET.tmp"; devlog_lock_release' EXIT
[ -d "$DEVLOG_DIR" ] && devlog_lock_acquire

# Normalise: trim, drop blank lines, ensure a "- " list prefix.
awk '
  { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
  $0 != "" { if ($0 !~ /^- /) $0 = "- " $0; print }
' "$RULES" > "$NEW"

if [ -f "$TARGET" ]; then
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b { g = 1; next } $0 == e { g = 0 } g' "$TARGET" > "$EXISTING"
fi

# FILENAME, not NR==FNR: an empty $EXISTING would make NR==FNR true for $NEW too.
awk -v ex="$EXISTING" 'FILENAME == ex { seen[$0] = 1; next } !seen[$0]++' "$EXISTING" "$NEW" > "$TO_ADD"

TOTAL="$(awk 'END { print NR }' "$NEW")"
ADDED="$(awk 'END { print NR }' "$TO_ADD")"
SKIPPED=$((TOTAL - ADDED))

if [ "$ADDED" -gt 0 ]; then
  if [ -f "$TARGET" ] && grep -qxF "$BEGIN_MARK" "$TARGET" && grep -qxF "$END_MARK" "$TARGET"; then
    awk -v e="$END_MARK" -v add="$TO_ADD" '
      $0 == e && !done { while ((getline l < add) > 0) print l; done = 1 }
      { print }
    ' "$TARGET" > "$TARGET.tmp" || exit 1
  else
    {
      if [ -s "$TARGET" ]; then
        cat "$TARGET"
        [ -n "$(tail -c 1 "$TARGET")" ] && printf '\n'
        printf '\n'
      fi
      printf '%s\n## devlog-tracker 沉澱的規範\n\n' "$BEGIN_MARK"
      cat "$TO_ADD"
      printf '%s\n' "$END_MARK"
    } > "$TARGET.tmp" || exit 1
  fi
  # Write back in place (not mv): TARGET may be a symlink (e.g. CLAUDE.md ->
  # AGENTS.md) or have a non-default mode; mv would replace it with a plain
  # 644 file and break the link. $TARGET.tmp is fully built above already,
  # so this is the only step that touches TARGET.
  cat "$TARGET.tmp" > "$TARGET" || exit 1
  rm -f "$TARGET.tmp"
fi

echo "ADDED=$ADDED SKIPPED_DUP=$SKIPPED TARGET=$TARGET"
