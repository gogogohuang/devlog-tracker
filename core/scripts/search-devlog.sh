#!/usr/bin/env bash
# Filesystem side of /devlog-tracker:search <關鍵字>. Plain read only -- no
# workspace verification, no wait-for-confirmation flow, same posture as
# overview.md / lessons.md. Greps every devlog*.md file under .devlog/:
# devlog.md, devlog.archive.md, kept devlog.<name>.md, and
# devlog.lessons.<topic>.md all match this one glob, so there is no
# per-file-type logic to keep in sync when a new kind of devlog file is
# added. Case-insensitive fixed-string match; not fence-aware (a match or a
# heading inside a ``` block is still reported) -- this is a navigation aid,
# not a Stop-grade verifier.
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_resolve_paths "$PROJECT_DIR"

KEYWORD="${1:-}"
if [ -z "$KEYWORD" ]; then
  echo "MISSING_KEYWORD" >&2
  exit 1
fi

if [ ! -d "$DEVLOG_DIR" ]; then
  echo "NO_INDEX"
  exit 0
fi

shopt -s nullglob
FILES=("$DEVLOG_DIR"/devlog*.md)
if [ ${#FILES[@]} -eq 0 ]; then
  echo "NO_INDEX"
  exit 0
fi

FOUND=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  leaf="${f##*/}"
  MATCHES="$(awk -v kw="$KEYWORD" '
    BEGIN { heading = "" }
    /^#{2,3} / { heading = $0 }
    {
      if (index(tolower($0), tolower(kw)) > 0) {
        h = heading
        gsub(/"/, "\\\"", h)
        printf "HEADING=\"%s\" LINE=%d: %s\n", h, NR, $0
      }
    }
  ' "$f")"
  if [ -n "$MATCHES" ]; then
    FOUND=1
    printf 'FILE=.devlog/%s\n' "$leaf"
    printf '%s\n' "$MATCHES"
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "NO_MATCH"
fi
