#!/usr/bin/env bash
# SessionEnd: stamp INTERRUPTED if a Round is still open.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
INPUT="$(cat 2>/dev/null || true)"

REASON="$(json_str_field "$INPUT" reason)"
[ -n "$REASON" ] || REASON="other"

bash "$HOOKS_DIR/close-open-round.sh" "SessionEnd:${REASON}" || true
exit 0
