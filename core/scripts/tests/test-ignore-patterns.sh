#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ignp.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
run() { DEVLOG_PROJECT_DIR="$TMP" bash "$SCRIPT_DIR/ignore-patterns.sh" "$@"; }
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; FAIL=1; }

OUT="$(run)"; case "$OUT" in "no .devlogignore"*) ok "list without file" ;; *) bad "list without file: $OUT" ;; esac
[ ! -e "$TMP/.devlogignore" ] && ok "list does not create" || bad "list created file"

run add '*.lock' >/dev/null; [ "$(cat "$TMP/.devlogignore")" = '*.lock' ] && ok "add creates" || bad "add creates"
OUT="$(run add '*.lock')"; case "$OUT" in already*) ok "dup reported" ;; *) bad "dup: $OUT" ;; esac
[ "$(wc -l < "$TMP/.devlogignore" | tr -d ' ')" = 1 ] && ok "no duplicate line" || bad "duplicate line"

printf '# c\ndist/' > "$TMP/.devlogignore"   # no trailing newline
run add '!keep.lock' >/dev/null
[ "$(cat "$TMP/.devlogignore")" = "$(printf '# c\ndist/\n!keep.lock')" ] && ok "add keeps content + newline" || bad "add newline: $(cat "$TMP/.devlogignore")"

OUT="$(run list)"; case "$OUT" in *"2: dist/"*) ok "list numbered" ;; *) bad "list: $OUT" ;; esac

run remove 'dist' >/dev/null; grep -qx 'dist/' "$TMP/.devlogignore" && ok "remove exact only" || bad "remove prefix match"
OUT="$(run remove 'dist/')"; case "$OUT" in removed*) ok "removed" ;; *) bad "remove: $OUT" ;; esac
grep -q '^# c$' "$TMP/.devlogignore" && ok "comment preserved" || bad "comment lost"
OUT="$(run remove 'nope')"; case "$OUT" in "not found"*) ok "remove missing" ;; *) bad "remove missing: $OUT" ;; esac
rm -f "$TMP/.devlogignore"
OUT="$(run remove 'x')"; case "$OUT" in "not found"*) ok "remove no file" ;; *) bad "remove no file: $OUT" ;; esac

OUT="$(run check a.lock)"; rc=$?
[ "$rc" -eq 0 ] && ok "check rc 0 ($OUT)" || bad "check rc $rc"

run bogus >/dev/null 2>&1; [ $? -eq 1 ] && ok "bad subcommand" || bad "bad subcommand"
run add >/dev/null 2>&1; [ $? -eq 1 ] && ok "add no arg" || bad "add no arg"
run remove >/dev/null 2>&1; [ $? -eq 1 ] && ok "remove no arg" || bad "remove no arg"
run check >/dev/null 2>&1; [ $? -eq 1 ] && ok "check no arg" || bad "check no arg"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
