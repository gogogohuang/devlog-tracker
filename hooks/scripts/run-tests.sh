#!/usr/bin/env bash
# Run every hook self-check. Usage: bash hooks/scripts/run-tests.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
shopt -s nullglob
for t in "$DIR"/test-*.sh; do
  echo "=== $(basename "$t") ==="
  if ! bash "$t"; then
    FAIL=1
  fi
done
echo "=== test-adapters.sh ==="
if ! bash "$DIR/../../cursor/hooks/test-adapters.sh"; then
  FAIL=1
fi
if [ "$FAIL" -ne 0 ]; then
  echo "Some hook self-checks FAILED."
  exit 1
fi
echo "All hook self-checks passed."
exit 0
