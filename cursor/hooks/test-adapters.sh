#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
assert_single_json() {
  local desc="$1" json="$2" count
  if command -v jq >/dev/null 2>&1; then
    count="$(printf '%s' "$json" | jq -s 'length' 2>/dev/null || echo '')"
  else
    # No jq: count top-level {...} closures ourselves, quote/escape-aware so
    # a brace inside a string value doesn't throw the depth count off.
    count="$(printf '%s' "$json" | awk '
      {
        line = $0
        for (i = 1; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (esc) { esc = 0; continue }
          if (c == "\\" && in_str) { esc = 1; continue }
          if (c == "\"") { in_str = !in_str; continue }
          if (in_str) continue
          if (c == "{") depth++
          else if (c == "}") { depth--; if (depth == 0) n_obj++ }
        }
      }
      END { print n_obj + 0 }
    ' 2>/dev/null || echo '')"
  fi
  if [ "$count" = "1" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected 1 top-level JSON value, got [$count]) [$json]"; FAIL=1
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

# submit prompt with stale 工作區 forwards additional_context
MIS="$TMP/mismatch-submit"
mkdir -p "$MIS/.devlog"
touch "$MIS/.devlog/.enabled"
git -C "$MIS" init -q -b main
git -C "$MIS" config user.email test@example.com
git -C "$MIS" config user.name test
echo hello > "$MIS/a.txt"
git -C "$MIS" add a.txt
git -C "$MIS" commit -q -m init
cat > "$MIS/.devlog/devlog.md" <<'EOF'
## Round 1 — 2026-09-11T00:00:00+08:00

### Handoff
#### 工作區
main @ deadbeef，工作樹乾淨
#### 現況
going
#### 下一步
do x

### Status
IN_PROGRESS
EOF
OUT="$(printf '{"workspace_roots":["%s"],"prompt":"keep going","session_id":"cursor-mismatch"}' "$MIS" | bash "$SCRIPT_DIR/on-submit-prompt.sh")"
case "$OUT" in *'"continue":true'*) echo "PASS: mismatch submit continues" ;; *) echo "FAIL: mismatch submit [$OUT]"; FAIL=1 ;; esac
case "$OUT" in *'"additional_context"'*工作區*) echo "PASS: mismatch submit additional_context" ;; *) echo "FAIL: mismatch context [$OUT]"; FAIL=1 ;; esac
assert_single_json "mismatch submit single json" "$OUT"
[ -f "$MIS/.devlog/.workspace-mismatch" ] && echo "PASS: mismatch submit writes marker" || { echo "FAIL: no cursor marker"; FAIL=1; }

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

# --- no-jq session_id must reach segment-state via round-start ------------
NOJQ_HOME="$TMP/nojq_home"
mkdir -p "$NOJQ_HOME/.devlog" "$TMP/nojq_path"
touch "$NOJQ_HOME/.devlog/.enabled"
printf '%s\n' '{"last_change_epoch": 0, "last_seen_cksum": "", "max_silent_seconds": 600, "session_id": ""}' \
  > "$NOJQ_HOME/.devlog/.segment-state"
CLEAN_PATH="$TMP/nojq_path"
# Resolve real binaries (zsh `command -v` may return aliases / builtins).
for cmd in bash sh cksum date grep sed cat mkdir tr mktemp rm head awk touch \
  pwd dirname uname ln printf sort cut wc env sleep; do
  src=""
  for cand in "/bin/$cmd" "/usr/bin/$cmd"; do
    if [ -x "$cand" ]; then src="$cand"; break; fi
  done
  [ -n "$src" ] && ln -sf "$src" "$CLEAN_PATH/$cmd"
done
# Explicitly do NOT link jq.
OUT="$(printf '{"workspace_roots":["%s"],"prompt":"nojq-hi","session_id":"cursor-nojq"}' "$NOJQ_HOME" \
  | env PATH="$CLEAN_PATH" bash "$SCRIPT_DIR/on-submit-prompt.sh")"
case "$OUT" in *'"continue":true'*) echo "PASS: nojq submit continues" ;; *) echo "FAIL: nojq submit [$OUT]"; FAIL=1 ;; esac
SEG_SID="$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$NOJQ_HOME/.devlog/.segment-state" 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
if [ "$SEG_SID" = "cursor-nojq" ]; then
  echo "PASS: nojq session_id stored in segment-state"
else
  echo "FAIL: nojq session_id missing (got [$SEG_SID])"; FAIL=1
fi

# --- no-jq PreToolUse deny must emit a single-line JSON object --------------
# segment-watch deny stderr is multiline; without newline escaping, bash 3.2
# prints unparseable JSON and Cursor fail-opens (valve vanishes).
OUT="$(printf '{"workspace_roots":["%s"],"tool_name":"Bash","tool_input":{},"session_id":"cursor-mismatch"}' "$MIS" \
  | env PATH="$CLEAN_PATH" bash "$SCRIPT_DIR/on-pre-tool.sh")"
case "$OUT" in *'"permission":"deny"'*) echo "PASS: nojq mismatch preTool denies" ;; *) echo "FAIL: nojq mismatch preTool [$OUT]"; FAIL=1 ;; esac
assert_single_json "nojq mismatch preTool deny single json" "$OUT"
case "$OUT" in
  *$'\n'*$'\n'*) echo "FAIL: nojq deny JSON contains raw newlines [$OUT]"; FAIL=1 ;;
  *) echo "PASS: nojq deny JSON has no raw newlines inside the string" ;;
esac
if command -v python3 >/dev/null 2>&1; then
  if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
    echo "PASS: nojq deny JSON is parseable"
  else
    echo "FAIL: nojq deny JSON is not parseable [$OUT]"; FAIL=1
  fi
fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
