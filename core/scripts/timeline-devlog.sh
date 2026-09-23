#!/usr/bin/env bash
# /devlog-tracker:timeline and `npx devlog-tracker timeline`
# (docs/design/read-side-and-promote.md C): report-devlog.sh --json --rounds
# piped into timeline-render.js, written to .devlog/timeline.html (gitignored).
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"

# Checked before sourcing anything: Claude plugin users may not have Node.
command -v node >/dev/null 2>&1 || { echo "NO_NODE"; exit 0; }

# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

ALL=0
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all-branches) ALL=1 ;;
    --out) shift; OUT="${1:-}" ;;
    *) echo "UNKNOWN_ARG=$1" >&2; exit 2 ;;
  esac
  shift
done

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
[ -d "$DEVLOG_DIR" ] || { echo "NOT_STARTED"; exit 0; }
[ -n "$OUT" ] || OUT="$DEVLOG_DIR/timeline.html"

ARGS=(--json --rounds)
[ "$ALL" -eq 1 ] && ARGS+=(--all-branches)

JSON_TMP="$(mktemp "${TMPDIR:-/tmp}/devlog-timeline.XXXXXX")" || exit 1
trap 'rm -f "$JSON_TMP" "$OUT.tmp"' EXIT
bash "$SCRIPT_DIR/report-devlog.sh" "${ARGS[@]}" > "$JSON_TMP" || exit 1
node "$SCRIPT_DIR/timeline-render.js" < "$JSON_TMP" > "$OUT.tmp" || exit 1
mv "$OUT.tmp" "$OUT" || exit 1

OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
echo "OUT=$OUT_DIR/$(basename "$OUT")"
