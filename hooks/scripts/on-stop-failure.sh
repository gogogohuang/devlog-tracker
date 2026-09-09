#!/usr/bin/env bash
# StopFailure: stamp INTERRUPTED unless this is a usage-exhaustion error.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat 2>/dev/null || true)"

ERROR=""
if command -v jq >/dev/null 2>&1; then
  ERROR="$(printf '%s' "$INPUT" | jq -r '.error // empty' 2>/dev/null || echo '')"
  if [ "$ERROR" = "null" ]; then ERROR=""; fi
else
  ERROR="$(printf '%s' "$INPUT" | grep -o '"error"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo '')"
fi

case "$ERROR" in
  rate_limit|billing_error|account_on_hold) exit 0 ;;
  '') ERROR="unknown" ;;
esac

bash "$HOOKS_DIR/close-open-round.sh" "StopFailure:${ERROR}" || true
exit 0
