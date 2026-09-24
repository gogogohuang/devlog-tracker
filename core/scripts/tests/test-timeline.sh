#!/usr/bin/env bash
# Self-check for timeline-devlog.sh (docs/design/read-side-and-promote.md C).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# --- NO_NODE: node missing from PATH (checked before anything else) ----------
EMPTY_BIN="$TMP_ROOT/empty-bin"
mkdir -p "$EMPTY_BIN"
BASH_BIN="$(command -v bash)"
OUT="$(PATH="$EMPTY_BIN" "$BASH_BIN" "$SCRIPT_DIR/timeline-devlog.sh" 2>&1)"
[ "$OUT" = "NO_NODE" ] && pass "no node -> NO_NODE" || fail "no node -> NO_NODE (got $OUT)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: remaining timeline checks need node"
  if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0; else echo "Some checks FAILED."; exit 1; fi
fi

# --- NOT_STARTED --------------------------------------------------------------
OUT="$(bash "$SCRIPT_DIR/timeline-devlog.sh")"
[ "$OUT" = "NOT_STARTED" ] && pass "no .devlog -> NOT_STARTED" || fail "NOT_STARTED (got $OUT)"
[ ! -e "$DEVLOG_DIR" ] && pass "NOT_STARTED creates nothing" || fail "NOT_STARTED created .devlog"

# --- End to end -----------------------------------------------------------------
mkdir -p "$DEVLOG_DIR"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF2'
## Round 1 — 2026-09-01T10:00:00+0800

### User Input
secret-input-text

### Summary
<script>alert(1)</script> 中文摘要

### Status
DONE
EOF2
OUT="$(bash "$SCRIPT_DIR/timeline-devlog.sh")"
case "$OUT" in
  "OUT=$(cd "$DEVLOG_DIR" && pwd)/timeline.html") pass "default OUT path is absolute .devlog/timeline.html" ;;
  *) fail "default OUT (got $OUT)" ;;
esac
HTML="$DEVLOG_DIR/timeline.html"
grep -q '中文摘要' "$HTML" && pass "summary rendered" || fail "summary missing"
grep -q '<script>alert' "$HTML" && fail "raw script tag leaked" || pass "script tag escaped"
grep -q 'secret-input-text' "$HTML" && fail "User Input leaked" || pass "User Input not included"
[ ! -e "$HTML.tmp" ] && pass "no leftover tmp file" || fail "leftover $HTML.tmp"

# --- --out ------------------------------------------------------------------------
OUT="$(bash "$SCRIPT_DIR/timeline-devlog.sh" --out "$TMP_ROOT/custom.html")"
[ -s "$TMP_ROOT/custom.html" ] && pass "--out writes the given path" || fail "--out ($OUT)"

# --- unknown arg ------------------------------------------------------------------
bash "$SCRIPT_DIR/timeline-devlog.sh" --bogus >/dev/null 2>&1
RC=$?
[ "$RC" -eq 2 ] && pass "unknown arg exits 2" || fail "unknown arg exit $RC"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
