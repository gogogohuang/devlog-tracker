#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
mkdir -p "$TMP/.devlog"
FAIL=0
check_exit_1() {
  bash "$SCRIPT_DIR/resume-devlog.sh" "$@" >/dev/null 2>&1
  [ "$?" -eq 1 ] && echo "PASS: $1 rejected" || { echo "FAIL: $1"; FAIL=1; }
}
check_exit_1 --name
check_exit_1 --name archive
check_exit_1 --name ../x
cat > "$TMP/.devlog/devlog.foo.md" <<'EOF'
# Kept log

## Round 4 — now

### Status
DONE
EOF
OUT="$(bash "$SCRIPT_DIR/resume-devlog.sh" --name devlog.foo.md)"
case "$OUT" in *"PATH=.devlog/devlog.foo.md"*) echo "PASS: path" ;; *) echo "FAIL: path [$OUT]"; FAIL=1 ;; esac
case "$OUT" in *"## Round 4"*) echo "PASS: content" ;; *) echo "FAIL: content"; FAIL=1 ;; esac
OUT="$(bash "$SCRIPT_DIR/resume-devlog.sh" --name missing 2>&1)"
[ "$?" -eq 1 ] || { echo "FAIL: missing exit"; FAIL=1; }
case "$OUT" in *"MISSING"*"CANDIDATES=foo"*) echo "PASS: candidates" ;; *) echo "FAIL: candidates [$OUT]"; FAIL=1 ;; esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
