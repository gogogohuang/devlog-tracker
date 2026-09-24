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

OPEN=""
[ ! -f "$DEVLOG_DIR/.round-open" ] || OPEN="$(json_int_get "$DEVLOG_DIR/.round-open" round)"

devlog_lock_acquire
trap 'devlog_lock_release' EXIT
node "$SCRIPT_DIR/keep-all.js" "$@" \
  --dir "$DEVLOG_DIR" --project "$PROJECT_DIR" --current "${DEVLOG_FILE##*/}" \
  --open "$OPEN" --origin "${DEVLOG_ORIGIN:-}"
