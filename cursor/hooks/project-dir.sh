#!/usr/bin/env bash
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
ROOT=""
if command -v jq >/dev/null 2>&1; then
  ROOT="$(printf '%s' "$INPUT" | jq -r '.workspace_roots[0] // empty' 2>/dev/null || true)"
fi
printf '%s\n' "${ROOT:-.}"
