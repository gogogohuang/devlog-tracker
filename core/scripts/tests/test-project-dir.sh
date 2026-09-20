#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="$(command -v bash)"
FAIL=0

run_case() {
  local desc="$1" expected="$2"
  shift 2
  local actual
  actual="$(env -i PATH="$PATH" "$@" "$BASH_BIN" -c '. "'"$DIR"'/project-dir.sh"; devlog_project_dir')"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected [$expected], got [$actual])"
    FAIL=1
  fi
}

run_case "neither var set falls back to ." "."
run_case "CLAUDE_PROJECT_DIR alone is honored" "/legacy" \
  CLAUDE_PROJECT_DIR=/legacy
run_case "DEVLOG_PROJECT_DIR alone is honored" "/neutral" \
  DEVLOG_PROJECT_DIR=/neutral
run_case "DEVLOG_PROJECT_DIR wins over CLAUDE_PROJECT_DIR" "/neutral" \
  DEVLOG_PROJECT_DIR=/neutral CLAUDE_PROJECT_DIR=/legacy

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1
fi
