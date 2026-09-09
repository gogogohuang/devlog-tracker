#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
assert_single_json() {
  local desc="$1" json="$2"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: $desc (python3 required to parse hook stdout)"; FAIL=1; return
  fi
  if printf '%s' "$json" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc [$json]"; FAIL=1
  fi
}
mkdir -p "$TMP/project/.devlog"
cat > "$TMP/project/.devlog/devlog.md" <<'EOF'
## Round 1 — now

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
OUT="$(printf '{"workspace_roots":["%s"]}' "$TMP/project" | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$OUT" in *'"additional_context"'*"Round 1"*) echo "PASS: sessionStart context" ;; *) echo "FAIL: sessionStart [$OUT]"; FAIL=1 ;; esac
assert_single_json "sessionStart single json" "$OUT"
EMPTY="$(printf '{}' | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$EMPTY" in \{*\}) echo "PASS: empty workspace valid json" ;; *) echo "FAIL: empty json [$EMPTY]"; FAIL=1 ;; esac
assert_single_json "empty workspace single json" "$EMPTY"

# submit prompt
SUBMIT="$TMP/submit"
mkdir -p "$SUBMIT/.devlog"
touch "$SUBMIT/.devlog/.enabled"
OUT="$(printf '{"workspace_roots":["%s"],"prompt":"hello","session_id":"cursor-1"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-submit-prompt.sh")"
case "$OUT" in *'"continue":true'*) echo "PASS: submit continues" ;; *) echo "FAIL: submit [$OUT]"; FAIL=1 ;; esac
assert_single_json "submit single json" "$OUT"
grep -q 'hello' "$SUBMIT/.devlog/devlog.md" && echo "PASS: submit writes round" || { echo "FAIL: submit round"; FAIL=1; }
ROUNDS="$(grep -c '^## Round ' "$SUBMIT/.devlog/devlog.md" || true)"
if [ "$ROUNDS" -eq 1 ]; then echo "PASS: submit writes one round"; else echo "FAIL: submit round count [$ROUNDS]"; FAIL=1; fi

# preToolUse allowlists writes to the devlog and denies expired other tools
NOW="$(date +%s)"
OLD=$((NOW - 1000))
SUM="$(cksum < "$SUBMIT/.devlog/devlog.md" | tr -d '\n')"
printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "max_silent_seconds": 900, "session_id": "cursor-1"}\n' "$OLD" "$SUM" > "$SUBMIT/.devlog/.segment-state"
OUT="$(printf '{"workspace_roots":["%s"],"tool_name":"Write","tool_input":{"file_path":"%s/.devlog/devlog.md"},"session_id":"cursor-1"}' "$SUBMIT" "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh")"
case "$OUT" in *'"permission":"deny"'*) echo "FAIL: devlog write denied"; FAIL=1 ;; *) echo "PASS: devlog write allowed" ;; esac
assert_single_json "preTool write single json" "$OUT"
OUT="$(printf '{"workspace_roots":["%s"],"tool_name":"StrReplace","tool_input":{"file_path":"%s/.devlog/devlog.md"},"session_id":"cursor-1"}' "$SUBMIT" "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh")"
case "$OUT" in *'"permission":"deny"'*) echo "FAIL: StrReplace devlog denied"; FAIL=1 ;; *) echo "PASS: StrReplace devlog allowed" ;; esac
assert_single_json "preTool StrReplace single json" "$OUT"
OUT="$(printf '{"workspace_roots":["%s"],"tool_name":"Bash","tool_input":{},"session_id":"cursor-1"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-pre-tool.sh")"
case "$OUT" in *permission*deny*"### 段落"*) echo "PASS: expired tool denied" ;; *) echo "FAIL: preTool [$OUT]"; FAIL=1 ;; esac
assert_single_json "preTool deny single json" "$OUT"

# stop: incomplete round asks Cursor for one follow-up; loop_count prevents retry
OUT="$(printf '{"workspace_roots":["%s"],"status":"completed","loop_count":0}' "$SUBMIT" | bash "$SCRIPT_DIR/on-stop.sh")"
case "$OUT" in *'"followup_message"'*"Summary"*) echo "PASS: stop followup" ;; *) echo "FAIL: stop [$OUT]"; FAIL=1 ;; esac
assert_single_json "stop followup single json" "$OUT"
OUT="$(printf '{"workspace_roots":["%s"],"status":"completed","loop_count":1}' "$SUBMIT" | bash "$SCRIPT_DIR/on-stop.sh")"
case "$OUT" in *followup_message*) echo "FAIL: loop guard followup"; FAIL=1 ;; *) echo "PASS: stop loop guard" ;; esac
assert_single_json "stop loop guard single json" "$OUT"
OUT="$(printf '{"workspace_roots":["%s"],"status":"running","loop_count":0}' "$SUBMIT" | bash "$SCRIPT_DIR/on-stop.sh")"
case "$OUT" in *followup_message*) echo "FAIL: non-completed stop enforced [$OUT]"; FAIL=1 ;; *) echo "PASS: non-completed stop skipped" ;; esac
assert_single_json "non-completed stop single json" "$OUT"

# aborted stop and session end close the open round
printf '%s\n' '{"round": 1, "opened_at": "now"}' > "$SUBMIT/.devlog/.round-open"
OUT="$(printf '{"workspace_roots":["%s"],"status":"aborted"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-stop.sh")"
grep -q 'INTERRUPTED' "$SUBMIT/.devlog/devlog.md" && echo "PASS: aborted closes round" || { echo "FAIL: aborted"; FAIL=1; }
assert_single_json "aborted stop single json" "$OUT"

# sessionEnd delegates its reason to the existing close helper
cat >> "$SUBMIT/.devlog/devlog.md" <<'EOF'

## Round 2 — now

### Status
IN_PROGRESS
EOF
printf '%s\n' '{"round": 2, "opened_at": "now"}' > "$SUBMIT/.devlog/.round-open"
cksum < "$SUBMIT/.devlog/devlog.md" > "$SUBMIT/.devlog/.turn-start"
OUT="$(printf '{"workspace_roots":["%s"],"reason":"windowClosed"}' "$SUBMIT" | bash "$SCRIPT_DIR/on-session-end.sh")"
grep -q 'SessionEnd:windowClosed' "$SUBMIT/.devlog/devlog.md" && echo "PASS: session end reason" || { echo "FAIL: session end"; FAIL=1; }
assert_single_json "sessionEnd single json" "$OUT"

# project-dir without jq still reads workspace_roots[0]
PATH_NO_JQ="$TMP/no-jq-path"
mkdir -p "$PATH_NO_JQ"
for bin in bash cat printf grep sed head mktemp rm date cksum awk tr mkdir; do
  bin_path="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$bin_path" ] && ln -sf "$bin_path" "$PATH_NO_JQ/$bin"
done
ROOT="$(printf '{"workspace_roots":["%s"]}' "$SUBMIT" | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/project-dir.sh")"
if [ "$ROOT" = "$SUBMIT" ]; then echo "PASS: project-dir without jq"; else echo "FAIL: project-dir without jq [$ROOT]"; FAIL=1; fi

# tool interruption marker
rm -f "$SUBMIT/.devlog/.interrupted"
OUT="$(printf '{"workspace_roots":["%s"],"is_interrupt":true}' "$SUBMIT" | bash "$SCRIPT_DIR/on-tool-failure.sh")"
[ -f "$SUBMIT/.devlog/.interrupted" ] && echo "PASS: tool interruption marked" || { echo "FAIL: interrupt marker"; FAIL=1; }
assert_single_json "toolFailure single json" "$OUT"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
