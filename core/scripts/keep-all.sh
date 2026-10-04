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

if [ "${1:-}" = "--write-analysis" ]; then
  # Validate the source before touching .devlog, and create .devlog if it is
  # missing: this mode must never report NOTHING without writing.
  SRC="${2:-}"
  [ -f "$SRC" ] || { echo "keep-all: analysis source not found: $SRC" >&2; exit 1; }
  grep -q '[^[:space:]]' "$SRC" || { echo "keep-all: analysis source is empty: $SRC" >&2; exit 1; }
  mkdir -p "$DEVLOG_DIR" || { echo "keep-all: cannot create devlog directory: $DEVLOG_DIR" >&2; exit 1; }
else
  [ -d "$DEVLOG_DIR" ] || { echo "NOTHING"; exit 0; }
fi

devlog_lock_acquire
trap 'devlog_lock_release' EXIT

if [ "${1:-}" = "--write-analysis" ]; then
  # Write only when this process holds the lock or legitimately inherits it
  # from a parent (DEVLOG_LOCK_OWNER matches the lock's pid). Anything else,
  # including a timeout on a lock with no valid pid, is a failed acquire.
  if [ "${LOCK_HELD:-0}" -ne 1 ]; then
    LOCK_PID="$(cat "$DEVLOG_DIR/.lock/pid" 2>/dev/null || true)"
    if [ -z "${DEVLOG_LOCK_OWNER:-}" ] || [ "$LOCK_PID" != "$DEVLOG_LOCK_OWNER" ]; then
      echo "keep-all: could not acquire devlog lock (held by ${LOCK_CONTENDED_BY:-unknown process})" >&2
      exit 1
    fi
  fi
  DEST="$(cd "$DEVLOG_DIR" && pwd)/keep-all.analysis.md"
  # mv would move the temp file into a directory (or a link to one) and still succeed.
  [ -d "$DEST" ] && { echo "keep-all: analysis destination is a directory: $DEST" >&2; exit 1; }
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
