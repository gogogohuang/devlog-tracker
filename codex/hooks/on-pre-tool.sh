#!/usr/bin/env bash
# Codex PreToolUse wrapper. Codex's "command" hooks use the same exit-code
# contract as Claude Code (0 = allow, 2 = block), so this only needs the
# cwd->CLAUDE_PROJECT_DIR translation; segment-watch.sh's stderr message
# propagates unchanged. Fail-open like the Cursor adapter: only an exit code of
# exactly 2 blocks; anything else (including a missing core/scripts dir or a
# crash) allows.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
PLUGIN_SCRIPTS="$(cd "$SCRIPT_DIR/../../core/scripts" 2>/dev/null && pwd)"
[ -d "$PLUGIN_SCRIPTS" ] || exit 0
# shellcheck source=../../core/scripts/json-field.sh
. "$PLUGIN_SCRIPTS/json-field.sh"
INPUT="$(cat 2>/dev/null || true)"
ROOT="$(printf '%s' "$INPUT" | bash "$SCRIPT_DIR/project-dir.sh")"
export DEVLOG_PROJECT_DIR="$ROOT"

codex_access_payload() {
  printf '{"tool_name":"%s","tool_input":{"file_path":".devlog/.round-current.md"},"session_id":"%s","agent_id":"%s"}' \
    "$1" "$(json_escape "$(json_str_field "$INPUT" session_id)")" "$(json_escape "$(json_str_field "$INPUT" agent_id)")"
}

TOOL_NAME="$(json_str_field "$INPUT" tool_name)"
if [ "$TOOL_NAME" = Bash ] || [ "$TOOL_NAME" = apply_patch ]; then
  if command -v jq >/dev/null 2>&1; then
    COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  else
    COMMAND="$(json_str_field "$INPUT" command)"
  fi
fi

# Codex CLI reads files through Bash. Permit a single cat of the current
# devlog while the core valve is blocking other tools.
if [ "$TOOL_NAME" = Bash ]; then
  CWD="$(json_str_field "$INPUT" cwd)"
  case "$COMMAND" in
    "cat $ROOT/.devlog/.round-current.md"|"cat \"$ROOT/.devlog/.round-current.md\"")
      INPUT="$(codex_access_payload Read)"
      ;;
    'cat .devlog/.round-current.md'|'cat ".devlog/.round-current.md"')
      [ "$CWD" != "$ROOT" ] || INPUT="$(codex_access_payload Read)"
      ;;
  esac
fi

# During a blocked segment, the core permits edits to the current devlog.
# Codex's file editor is apply_patch, whose only file path is inside the patch
# string. Normalize only patches that exclusively add/update that file.
if [ "$TOOL_NAME" = apply_patch ]; then
  CWD="$(json_str_field "$INPUT" cwd)"
  [ -n "$CWD" ] || CWD="$ROOT"
  PATCH="$COMMAND"
  if printf '%s\n' "$PATCH" | awk -v cwd="$CWD" -v root="$ROOT" '
    function normalize(path, count, parts, stack, depth, i, result) {
      if (substr(path, 1, 1) != "/") path = cwd "/" path
      count = split(path, parts, "/")
      depth = 0
      for (i = 1; i <= count; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (depth > 0) depth--; continue }
        stack[++depth] = parts[i]
      }
      result = ""
      for (i = 1; i <= depth; i++) result = result "/" stack[i]
      return result == "" ? "/" : result
    }
    NR == 1 && $0 != "*** Begin Patch" { bad = 1 }
    /^\*\*\* (Add|Update|Delete) File: / {
      path = $0; sub(/^\*\*\* (Add|Update|Delete) File: /, "", path)
      if ($0 ~ /^\*\*\* Delete File: / || normalize(path) != normalize(root "/.devlog/.round-current.md")) bad = 1
      files++
    }
    /^\*\*\* Move to: / { bad = 1 }
    $0 == "*** End Patch" { ended = 1; next }
    END { exit !(files > 0 && ended && !bad) }
  '; then
    INPUT="$(codex_access_payload Write)"
  fi
fi
printf '%s' "$INPUT" | bash "$PLUGIN_SCRIPTS/segment-watch.sh"
RC=$?
if [ "$RC" -eq 2 ]; then
  printf 'Codex CLI：先用 cat "%s/.devlog/.round-current.md" 讀取，再用 apply_patch 只修改這份檔案；完成後重試原工具。\n' "$ROOT" >&2
  exit 2
fi
exit 0
