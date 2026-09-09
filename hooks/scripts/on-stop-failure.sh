#!/usr/bin/env bash
# StopFailure: stamp INTERRUPTED unless this is a usage-exhaustion error.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=json-field.sh
. "$HOOKS_DIR/json-field.sh"
INPUT="$(cat 2>/dev/null || true)"

ERROR="$(json_str_field "$INPUT" error)"

case "$ERROR" in
  rate_limit|billing_error|account_on_hold) exit 0 ;;
  '') ERROR="unknown" ;;
esac

bash "$HOOKS_DIR/close-open-round.sh" "StopFailure:${ERROR}" || true
exit 0
