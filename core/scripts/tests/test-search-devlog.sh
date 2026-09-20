#!/usr/bin/env bash
# Self-check for search-devlog.sh (/devlog-tracker:search), a pure-read
# lightweight grep across every devlog*.md file under .devlog/ -- devlog.md,
# devlog.archive.md, kept devlog.<name>.md, devlog.lessons.<topic>.md, and
# branch-scoped files all match the same glob, so there is no per-type logic
# to keep in sync.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"

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
    *) echo "FAIL: $desc (expected to contain '$needle', got: $haystack)"; FAIL=1 ;;
  esac
}
assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $desc (expected NOT to contain '$needle')"; FAIL=1 ;;
    *) echo "PASS: $desc" ;;
  esac
}

# --- No .devlog/ at all -> NO_INDEX ----------------------------------------
OUT="$(bash "$SCRIPT_DIR/search-devlog.sh" "foo" 2>&1)"
RC=$?
assert_exit "no .devlog/ -> exit 0" 0 "$RC"
[ "$OUT" = "NO_INDEX" ] && echo "PASS: no .devlog/ -> NO_INDEX" || { echo "FAIL: expected NO_INDEX, got: $OUT"; FAIL=1; }

mkdir -p "$DEVLOG_DIR"

# --- Missing keyword argument -> error, no files touched -------------------
bash "$SCRIPT_DIR/search-devlog.sh" >/dev/null 2>&1
assert_exit "missing keyword -> exit 1" 1 $?

# --- .devlog/ exists but has no devlog*.md files yet -> NO_INDEX -----------
OUT="$(bash "$SCRIPT_DIR/search-devlog.sh" "foo" 2>&1)"
[ "$OUT" = "NO_INDEX" ] && echo "PASS: empty .devlog/ -> NO_INDEX" || { echo "FAIL: expected NO_INDEX, got: $OUT"; FAIL=1; }

# --- Matches across main, archive, kept and lessons files -------------------
cat > "$DEVLOG_DIR/devlog.md" <<'EOF'
## Round 1 — 2026-09-08T00:00:00+08:00

### Summary
討論 span mode 的門檻設計。

### Status
DONE
EOF

cat > "$DEVLOG_DIR/devlog.archive.md" <<'EOF'
## Round 0 — 2026-09-01T00:00:00+08:00

### Summary
舊的 span mode 討論，已封存。

### Status
DONE
EOF

cat > "$DEVLOG_DIR/devlog.keep-plan.md" <<'EOF'
## Round 5 — 2026-09-05T00:00:00+08:00

### Summary
跟 keep 完全無關的一輪，內容是別的主題。

### Status
DONE
EOF

cat > "$DEVLOG_DIR/devlog.lessons.span-mode.md" <<'EOF'
## 2026-09-10T00:00:00+08:00

Span Mode 的門檻一開始設太低，導致誤判。
EOF

OUT="$(bash "$SCRIPT_DIR/search-devlog.sh" "span mode" 2>&1)"
RC=$?
assert_exit "search finds hits -> exit 0" 0 "$RC"
assert_contains "hit in devlog.md" "FILE=.devlog/devlog.md" "$OUT"
assert_contains "hit in devlog.archive.md" "FILE=.devlog/devlog.archive.md" "$OUT"
assert_contains "hit in devlog.lessons.span-mode.md" "FILE=.devlog/devlog.lessons.span-mode.md" "$OUT"
assert_not_contains "no hit in unrelated kept file" "FILE=.devlog/devlog.keep-plan.md" "$OUT"
assert_contains "match line reports nearest (###) heading" 'HEADING="### Summary"' "$OUT"
assert_contains "match line reports the matched text" "討論 span mode 的門檻設計" "$OUT"

# --- Heading context falls back to the nearest ## when no ### is closer ----
cat > "$DEVLOG_DIR/devlog.no-sub.md" <<'EOF'
## Round 9 — 2026-09-12T00:00:00+08:00
span mode 直接寫在 Round 標題底下，沒有任何 ### 子標題。
EOF
OUT_NOSUB="$(bash "$SCRIPT_DIR/search-devlog.sh" "span mode" 2>&1)"
assert_contains "falls back to nearest ## heading" 'HEADING="## Round 9' "$OUT_NOSUB"

# --- Case-insensitive match --------------------------------------------------
OUT_UPPER="$(bash "$SCRIPT_DIR/search-devlog.sh" "SPAN MODE" 2>&1)"
assert_contains "case-insensitive match" "FILE=.devlog/devlog.md" "$OUT_UPPER"

# --- No hits anywhere -> NO_MATCH -------------------------------------------
OUT_NONE="$(bash "$SCRIPT_DIR/search-devlog.sh" "找不到的關鍵字xyz" 2>&1)"
[ "$OUT_NONE" = "NO_MATCH" ] && echo "PASS: no hits -> NO_MATCH" || { echo "FAIL: expected NO_MATCH, got: $OUT_NONE"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks FAILED."
  exit 1
fi
