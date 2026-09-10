#!/usr/bin/env bash
# Self-check for await-open.sh. Run:
#   bash hooks/scripts/test-await-open.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
mkdir -p "$DEVLOG_DIR"

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

# --- 1: not enabled -> NOT_ENABLED, no file --------------------------------
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_exit "not enabled -> exit 1" 1 $?
assert_contains "reports NOT_ENABLED" "NOT_ENABLED" "$OUT"
if [ -f "$DEVLOG_DIR/.awaiting-reply" ]; then
  echo "FAIL: .awaiting-reply should not exist when disabled"
  FAIL=1
else
  echo "PASS: no .awaiting-reply when disabled"
fi

touch "$DEVLOG_DIR/.enabled"

# --- 2: resolves round from .round-open when present -----------------------
printf '%s\n' '{"round": 4, "opened_at": "2026-09-09T12:00:00+08:00"}' > "$DEVLOG_DIR/.round-open"
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_exit "opens -> exit 0" 0 $?
assert_contains "reports OPENED=4" "OPENED=4" "$OUT"
ROUND_FIELD="$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]\+' "$DEVLOG_DIR/.awaiting-reply" | grep -o '[0-9]\+$')"
if [ "$ROUND_FIELD" = "4" ]; then
  echo "PASS: .awaiting-reply round=4 (from .round-open)"
else
  echo "FAIL: expected round=4, got $ROUND_FIELD"
  FAIL=1
fi
grep -q '"opened_at"' "$DEVLOG_DIR/.awaiting-reply" \
  && echo "PASS: opened_at field present" || { echo "FAIL: opened_at missing"; FAIL=1; }
rm -f "$DEVLOG_DIR/.awaiting-reply" "$DEVLOG_DIR/.round-open"

# --- 3: falls back to last ## Round in devlog.md when .round-open absent ---
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-09T12:00:00+08:00

### Summary
done

### Handoff
#### 現況
done

### Status
DONE

## Round 2 — 2026-09-09T13:00:00+08:00

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_contains "falls back to last Round in devlog.md" "OPENED=2" "$OUT"
rm -f "$DEVLOG_DIR/.awaiting-reply"

# --- 4: already open -> ALREADY_OPEN, does not overwrite --------------------
printf '%s\n' '{"round": 99, "opened_at": "sentinel"}' > "$DEVLOG_DIR/.awaiting-reply"
OUT="$(bash "$SCRIPT_DIR/await-open.sh")"
assert_exit "already open -> exit 1" 1 $?
assert_contains "reports ALREADY_OPEN" "ALREADY_OPEN" "$OUT"
grep -q 'sentinel' "$DEVLOG_DIR/.awaiting-reply" \
  && echo "PASS: existing marker left untouched" || { echo "FAIL: existing marker was overwritten"; FAIL=1; }
rm -f "$DEVLOG_DIR/.awaiting-reply" "$DEVLOG_DIR/devlog.md"

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
