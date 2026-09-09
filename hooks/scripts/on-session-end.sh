#!/usr/bin/env bash
# SessionEnd: stamp INTERRUPTED if a Round is still open.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat 2>/dev/null || true)"

REASON=""
if command -v jq >/dev/null 2>&1; then
  REASON="$(printf '%s' "$INPUT" | jq -r '.reason // empty' 2>/dev/null || echo '')"
  if [ "$REASON" = "null" ]; then REASON=""; fi
else
  REASON="$(printf '%s' "$INPUT" | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi
[ -n "$REASON" ] || REASON="other"

bash "$HOOKS_DIR/close-open-round.sh" "SessionEnd:${REASON}" || true
exit 0
