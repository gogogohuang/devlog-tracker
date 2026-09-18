#!/usr/bin/env bash
# Codex hook payloads carry the project directory in a "cwd" field (unlike
# Cursor's workspace_roots[0] array). Same job as cursor/hooks/project-dir.sh,
# different field name.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
ROOT=""
if command -v jq >/dev/null 2>&1; then
  ROOT="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
else
  ROOT="$(printf '%s' "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
fi
printf '%s\n' "${ROOT:-.}"
