#!/usr/bin/env bash
# /devlog-tracker:keep-all (docs/design/keep-all.md). Resolves the current
# branch's devlog, holds the devlog lock, and hands off to keep-all.js:
#   keep-all.sh --scan
#   keep-all.sh --apply <plan.tsv> --fingerprint <fp> --count <n>
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"

# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_resolve_paths "$PROJECT_DIR"
[ -d "$DEVLOG_DIR" ] || { echo "NOTHING"; exit 0; }

devlog_lock_acquire
trap 'devlog_lock_release' EXIT

# Pure shell, handled before the Node check: plugin users may not have Node.
if [ "${1:-}" = "--write-analysis" ]; then
  SRC="${2:-}"
  [ -f "$SRC" ] || { echo "keep-all: analysis source not found: $SRC" >&2; exit 1; }
  DEST="$(cd "$DEVLOG_DIR" && pwd)/keep-all.analysis.md"
  TMP_DEST="$DEST.tmp.$$"
  cp "$SRC" "$TMP_DEST" && mv "$TMP_DEST" "$DEST" || { rm -f "$TMP_DEST"; exit 1; }
  echo "ANALYSIS=$DEST"
  exit 0
fi

command -v node >/dev/null 2>&1 || { echo "NO_NODE"; exit 0; }
OPEN_ROW="$(devlog_single_open_round)" || exit 1
OPEN="$(printf '%s' "$OPEN_ROW" | cut -f2)"
node "$SCRIPT_DIR/keep-all.js" "$@" \
  --dir "$DEVLOG_DIR" --project "$PROJECT_DIR" --current "${DEVLOG_FILE##*/}" \
  --open "$OPEN" --origin "${DEVLOG_ORIGIN:-}"
