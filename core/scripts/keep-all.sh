#!/usr/bin/env bash
# /devlog-tracker:keep-all (docs/design/keep-all.md). Resolves the current
# branch's devlog, holds the devlog lock, and hands off to keep-all.js:
#   keep-all.sh --scan
#   keep-all.sh --apply <plan.tsv> --fingerprint <fp> --count <n>
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"

# Checked before sourcing anything: Claude plugin users may not have Node.
# --write-analysis is pure shell, so it is exempt.
if [ "${1:-}" != "--write-analysis" ]; then
  command -v node >/dev/null 2>&1 || { echo "NO_NODE"; exit 0; }
fi

# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_resolve_paths "$PROJECT_DIR"
[ -d "$DEVLOG_DIR" ] || { echo "NOTHING"; exit 0; }

devlog_lock_acquire
trap 'devlog_lock_release' EXIT

if [ "${1:-}" = "--write-analysis" ]; then
  if [ -n "${LOCK_CONTENDED_BY:-}" ]; then
    echo "keep-all: devlog lock is held by process ${LOCK_CONTENDED_BY}" >&2
    exit 1
  fi
  SRC="${2:-}"
  [ -f "$SRC" ] || { echo "keep-all: analysis source not found: $SRC" >&2; exit 1; }
  grep -q '[^[:space:]]' "$SRC" || { echo "keep-all: analysis source is empty: $SRC" >&2; exit 1; }
  DEST="$(cd "$DEVLOG_DIR" && pwd)/keep-all.analysis.md"
  # mktemp creates the file exclusively (O_EXCL), so a pre-planted symlink
  # cannot redirect the copy outside .devlog.
  TMP_DEST="$(mktemp "$DEST.tmp.XXXXXX")" || exit 1
  if ! cp "$SRC" "$TMP_DEST"; then
    rm -f "$TMP_DEST"
    echo "keep-all: failed to write analysis temp file: $TMP_DEST" >&2
    exit 1
  fi
  if ! mv "$TMP_DEST" "$DEST"; then
    rm -f "$TMP_DEST"
    echo "keep-all: failed to move analysis into place: $DEST" >&2
    exit 1
  fi
  echo "ANALYSIS=$DEST"
  exit 0
fi

OPEN_ROW="$(devlog_single_open_round)" || exit 1
OPEN="$(printf '%s' "$OPEN_ROW" | cut -f2)"
node "$SCRIPT_DIR/keep-all.js" "$@" \
  --dir "$DEVLOG_DIR" --project "$PROJECT_DIR" --current "${DEVLOG_FILE##*/}" \
  --open "$OPEN" --origin "${DEVLOG_ORIGIN:-}"
