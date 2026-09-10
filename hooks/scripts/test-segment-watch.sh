#!/usr/bin/env bash
# Self-check for segment-watch.sh (+ round-start.sh clock reset in later
# scenarios). No framework — plain assert-and-exit. Run directly:
#   bash hooks/scripts/test-segment-watch.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"
touch "$DEVLOG_DIR/.enabled"
printf 'seed\n' > "$DEVLOG_DIR/devlog.md"
SEED_CKSUM="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"

FAIL=0
assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=1
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (missing: $needle)"; FAIL=1 ;;
  esac
}

write_state() {
  local epoch="$1" sum="$2" max="$3"
  printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "max_silent_seconds": %s, "session_id": "aaa"}\n' \
    "$epoch" "$sum" "$max" > "$DEVLOG_DIR/.segment-state"
}

NOW="$(date +%s)"
EXPIRED="$((NOW - 960))"
BASH_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
WRITE_REL='{"tool_name":"Write","tool_input":{"file_path":".devlog/devlog.md"}}'
WRITE_ABS="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.devlog/devlog.md"}}' "$TMP_ROOT")"
WRITE_OTHER='{"tool_name":"Write","tool_input":{"file_path":"src/foo.ts"}}'
EDIT_REL='{"tool_name":"Edit","tool_input":{"file_path":".devlog/devlog.md"}}'
STRREPLACE_REL='{"tool_name":"StrReplace","tool_input":{"file_path":".devlog/devlog.md"}}'

# --- Scenario 1: no .enabled -> exit 0 ------------------------------------
rm -f "$DEVLOG_DIR/.enabled"
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "no .enabled -> allowed" 0 $?
touch "$DEVLOG_DIR/.enabled"

# --- Scenario 2: fresh clock, Bash immediately -> exit 0 --------------------
write_state "$NOW" "$SEED_CKSUM" 900
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "fresh epoch, Bash -> allowed" 0 $?

# --- Scenario 3: expired + Bash -> exit 2 + stderr phrase -------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
ERR="$(printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" 2>&1 >/dev/null)"
assert_exit "expired + Bash -> blocked" 2 $?
assert_contains "block message names ### 段落" "### 段落" "$ERR"
assert_contains "block message names 門檻 900" "門檻 900 秒" "$ERR"
assert_contains "block message starts 這一輪已經" "這一輪已經" "$ERR"
assert_contains "block message ends 寫完再繼續呼叫其他工具" "寫完再繼續呼叫其他工具" "$ERR"

# --- Scenario 3b: only the parent session uses this valve -------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Bash","session_id":"aaa"}' | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + matching session_id -> blocked" 2 $?
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Bash","session_id":"bbb"}' | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + different session_id -> allowed" 0 $?
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Bash"}' | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + missing session_id -> blocked" 2 $?

# --- expired + Read / Grep / agent_id (unblock plan) ------------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":".devlog/devlog.md"},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Read devlog.md -> allowed" 0 $?

write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Read other -> blocked" 2 $?

write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Grep","tool_input":{"path":".devlog/devlog.md","pattern":"Round"},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Grep devlog.md -> allowed" 0 $?

write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Bash","tool_input":{},"session_id":"aaa","agent_id":"agent-xyz"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + agent_id -> allowed" 0 $?

write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' '{"tool_name":"Bash","tool_input":{},"session_id":"aaa","agent_id":""}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + empty agent_id -> blocked" 2 $?

write_state "$EXPIRED" "$SEED_CKSUM" 900
ERR="$(printf '%s' '{"tool_name":"Bash","tool_input":{},"session_id":"aaa"}' \
  | bash "$SCRIPT_DIR/segment-watch.sh" 2>&1 >/dev/null || true)"
case "$ERR" in
  *Read*.devlog/devlog.md*禁止*覆寫*) echo "PASS: stderr instructs Read then append" ;;
  *) echo "FAIL: stderr [$ERR]"; FAIL=1 ;;
esac

# --- Scenario 4: expired + Write relative devlog.md -> exit 0 ---------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_REL" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write .devlog/devlog.md -> allowed" 0 $?

# --- Scenario 5: expired + Write absolute path ending in /.devlog/devlog.md -
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_ABS" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write absolute /.devlog/devlog.md -> allowed" 0 $?

# --- Scenario 6: expired + Edit relative devlog.md -> exit 0 -----------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$EDIT_REL" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Edit .devlog/devlog.md -> allowed" 0 $?

write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$STRREPLACE_REL" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + StrReplace .devlog/devlog.md -> allowed" 0 $?

# --- Scenario 7: expired + Write other file -> exit 2 -----------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_OTHER" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write other file -> blocked" 2 $?

# --- Scenario 8: hash changed since last_seen -> exit 0 and persist ---------
write_state "$EXPIRED" "stale-sum" 900
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "hash differs from last_seen_cksum -> allowed" 0 $?
SEEN_AFTER="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
EPOCH_AFTER="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
MAX_AFTER="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
if [ "$SEEN_AFTER" = "$SEED_CKSUM" ] && [ "$EPOCH_AFTER" -ge "$NOW" ] && [ "$MAX_AFTER" = "900" ]; then
  echo "PASS: hash-change persist updated cksum/epoch and left max_silent_seconds=900"
else
  echo "FAIL: persist expected cksum=$SEED_CKSUM epoch>=$NOW max=900, got cksum=$SEEN_AFTER epoch=$EPOCH_AFTER max=$MAX_AFTER"
  FAIL=1
fi

# --- Scenario 9: malformed state -> fail-open --------------------------------
echo 'not json' > "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "malformed .segment-state -> allowed" 0 $?

# --- Scenario 10: missing .segment-state -> fail-open ------------------------
rm -f "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "missing .segment-state -> allowed" 0 $?

# --- Scenario 11: span open does NOT disable the valve ----------------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
cat > "$DEVLOG_DIR/.span-open" <<'SPANEOF'
{"round": 1, "opened_at": "2026-09-09T00:00:00+08:00", "ticks_since_checkin": 1, "max_silent_ticks": 5}
SPANEOF
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + open under-budget span + Bash -> still blocked" 2 $?
rm -f "$DEVLOG_DIR/.span-open"

# --- Scenario 12: no jq, expired + Bash still blocks ------------------------
PATH_NO_JQ="$TMP_ROOT/no-jq-path"
mkdir -p "$PATH_NO_JQ"
for bin in bash cat printf cksum date grep sed awk mv tr head; do
  bin_path="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$bin_path" ] && ln -sf "$bin_path" "$PATH_NO_JQ/$bin"
done
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$BASH_PAYLOAD" | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Bash without jq -> blocked" 2 $?
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_REL" | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + Write without jq -> allowed" 0 $?
WRITE_SPACED='{ "tool_name" : "Write" , "tool_input": {"file_path":".devlog/devlog.md"} }'
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '%s' "$WRITE_SPACED" | PATH="$PATH_NO_JQ" bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + spaced Write without jq -> allowed" 0 $?

# --- Scenario 12b: expired + empty stdin -> fail-open exit 0 ----------------
write_state "$EXPIRED" "$SEED_CKSUM" 900
printf '' | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "expired + empty stdin -> allowed" 0 $?

# --- Scenario 13: round-start.sh resets clock and preserves max -------------
write_state 1 "old-sum" 600
bash "$SCRIPT_DIR/round-start.sh" < /dev/null
POST_SKEL="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"
RS_EPOCH="$(grep -o '"last_change_epoch"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
RS_SUM="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
RS_MAX="$(grep -o '"max_silent_seconds"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.segment-state" | grep -o '[0-9]\+$')"
if [ "$RS_EPOCH" -ge "$NOW" ] && [ "$RS_SUM" = "$POST_SKEL" ] && [ "$RS_MAX" = "600" ]; then
  echo "PASS: round-start.sh reset epoch/cksum to post-skeleton hash and kept max_silent_seconds=600"
else
  echo "FAIL: round-start expected epoch>=$NOW cksum=$POST_SKEL max=600, got epoch=$RS_EPOCH cksum=$RS_SUM max=$RS_MAX"
  FAIL=1
fi
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "immediately after round-start.sh, Bash -> allowed" 0 $?

# --- Scenario 14: missing last_seen_cksum key -> fail-open ------------------
printf '{"last_change_epoch": 1, "max_silent_seconds": 900}\n' > "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "segment-state missing last_seen_cksum key -> allowed" 0 $?

# --- Scenario 15: identity match skips cksum but still blocks when expired --
# round-start may have rewritten the file; re-seed so cksum matches identity.
printf 'seed\n' > "$DEVLOG_DIR/devlog.md"
SEED_CKSUM="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"

file_identity() {
  local f="$1" mt sz
  if mt="$(stat -f '%m' "$f" 2>/dev/null)" && sz="$(stat -f '%z' "$f" 2>/dev/null)"; then
    printf '%s %s\n' "$mt" "$sz"
    return 0
  fi
  if mt="$(stat -c '%Y' "$f" 2>/dev/null)" && sz="$(stat -c '%s' "$f" 2>/dev/null)"; then
    printf '%s %s\n' "$mt" "$sz"
    return 0
  fi
  return 1
}

ID_LINE="$(file_identity "$DEVLOG_DIR/devlog.md")"
ID_MT="${ID_LINE%% *}"
ID_SZ="${ID_LINE#* }"
printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "last_seen_mtime": "%s", "last_seen_size": "%s", "max_silent_seconds": 900, "session_id": "aaa"}\n' \
  "$EXPIRED" "$SEED_CKSUM" "$ID_MT" "$ID_SZ" > "$DEVLOG_DIR/.segment-state"

SPY="$TMP_ROOT/spybin"
mkdir -p "$SPY"
REAL_CKSUM="$(command -v cksum)"
rm -f "$TMP_ROOT/cksum_count"
cat > "$SPY/cksum" <<EOF
#!/usr/bin/env bash
echo 1 >> "$TMP_ROOT/cksum_count"
exec "$REAL_CKSUM" "\$@"
EOF
chmod +x "$SPY/cksum"
printf '%s' "$BASH_PAYLOAD" | PATH="$SPY:$PATH" bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "identity match + expired -> still blocked" 2 $?
if [ ! -f "$TMP_ROOT/cksum_count" ]; then
  echo "PASS: identity match skipped cksum"
else
  echo "FAIL: cksum was invoked despite matching identity"
  FAIL=1
fi

# --- Scenario 16: identity mismatch forces cksum and clears silence ---------
printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "last_seen_mtime": "%s", "last_seen_size": "%s", "max_silent_seconds": 900, "session_id": "aaa"}\n' \
  "$EXPIRED" "$SEED_CKSUM" "$ID_MT" "$ID_SZ" > "$DEVLOG_DIR/.segment-state"
printf 'x' >> "$DEVLOG_DIR/devlog.md"
NEW_CKSUM="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "mtime/size change -> allowed (re-hash)" 0 $?
SEEN_MT="$(grep -o '"last_seen_mtime"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_mtime"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
SEEN_SZ="$(grep -o '"last_seen_size"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_size"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
SEEN_SUM="$(grep -o '"last_seen_cksum"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVLOG_DIR/.segment-state" | sed 's/.*"last_seen_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
ID_LINE2="$(file_identity "$DEVLOG_DIR/devlog.md")"
ID_MT2="${ID_LINE2%% *}"
ID_SZ2="${ID_LINE2#* }"
if [ "$SEEN_MT" = "$ID_MT2" ] && [ "$SEEN_SZ" = "$ID_SZ2" ] && [ "$SEEN_SUM" = "$NEW_CKSUM" ]; then
  echo "PASS: identity mismatch refreshed cksum + identity fields"
else
  echo "FAIL: expected mtime=$ID_MT2 size=$ID_SZ2 cksum=$NEW_CKSUM, got mtime=$SEEN_MT size=$SEEN_SZ cksum=$SEEN_SUM"
  FAIL=1
fi

# --- Scenario 17: missing identity fields fall through to cksum -------------
printf 'seed\n' > "$DEVLOG_DIR/devlog.md"
SEED_CKSUM="$(cksum < "$DEVLOG_DIR/devlog.md" | tr -d '\n')"
printf '{"last_change_epoch": %s, "last_seen_cksum": "%s", "max_silent_seconds": 900, "session_id": "aaa"}\n' \
  "$EXPIRED" "$SEED_CKSUM" > "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "missing identity fields + expired -> still blocked via cksum" 2 $?

printf '{"last_change_epoch": %s, "last_seen_cksum": "stale-sum", "max_silent_seconds": 900, "session_id": "aaa"}\n' \
  "$EXPIRED" > "$DEVLOG_DIR/.segment-state"
printf '%s' "$BASH_PAYLOAD" | bash "$SCRIPT_DIR/segment-watch.sh" >/dev/null 2>&1
assert_exit "missing identity + hash change -> allowed" 0 $?

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
