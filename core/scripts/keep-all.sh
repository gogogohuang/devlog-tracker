#!/usr/bin/env bash
# /devlog-tracker:keep-all (docs/design/keep-all.md). Resolves the current
# branch's devlog, holds the devlog lock, and hands off to keep-all.js:
#   keep-all.sh --scan
#   keep-all.sh --apply <plan.tsv> --fingerprint <fp> --count <n>
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"

# Checked before sourcing anything: Claude plugin users may not have Node.
command -v node >/dev/null 2>&1 || { echo "NO_NODE"; exit 0; }

# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"
# shellcheck source=json-field.sh
. "$SCRIPT_DIR/json-field.sh"

PROJECT_DIR="${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
devlog_resolve_paths "$PROJECT_DIR"
[ -d "$DEVLOG_DIR" ] || { echo "NOTHING"; exit 0; }

devlog_lock_acquire
trap 'devlog_lock_release' EXIT
OPEN_ROW="$(devlog_single_open_round)" || exit 1
OPEN="$(printf '%s' "$OPEN_ROW" | cut -f2)"
node "$SCRIPT_DIR/keep-all.js" "$@" \
  --dir "$DEVLOG_DIR" --project "$PROJECT_DIR" --current "${DEVLOG_FILE##*/}" \
  --open "$OPEN" --origin "${DEVLOG_ORIGIN:-}"
