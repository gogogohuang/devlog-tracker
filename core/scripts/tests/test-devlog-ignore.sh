#!/usr/bin/env bash
# Matcher table for devlog-ignore.sh (design D2) + fail-open behaviour.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$SCRIPT_DIR/devlog-ignore.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

# check "<patterns, \n separated>" path expected(ignored|kept)
check() {
  local pats="$1" path="$2" want="$3" got=kept
  printf '%b' "$pats" > "$TMP/.devlogignore"
  devlog_ignored "$TMP" "$path" && got=ignored
  if [ "$got" = "$want" ]; then echo "PASS: [$pats] $path -> $want"
  else echo "FAIL: [$pats] $path expected $want got $got"; FAIL=1; fi
}

check '*.lock\n' 'yarn.lock' ignored
check '*.lock\n' 'sub/dir/yarn.lock' ignored
check '*.lock\n' 'yarn.lock.txt' kept
check '# comment\n\n*.log\n' '# comment' kept
check '*.log\r\n' 'a.log' ignored
check '*.log   \n' 'a.log' ignored
check 'node_modules\n' 'a/node_modules/x/y.js' ignored
check 'node_modules\n' 'node_modules_x/y.js' kept
check 'dist/\n' 'dist/a.js' ignored
check 'dist/\n' 'dist/' ignored
check 'dist/\n' 'dist' kept
check 'dist/\n' 'src/dist/a.js' ignored
check '/build\n' 'build/x' ignored
check '/build\n' 'src/build/x' kept
check 'src/gen/*.ts\n' 'src/gen/a.ts' ignored
check 'src/gen/*.ts\n' 'src/gen/deep/a.ts' kept
check 'src/gen/*.ts\n' 'x/src/gen/a.ts' kept
check '*.md\n!README.md\n' 'README.md' kept
check '*.md\n!README.md\n' 'NOTES.md' ignored
check '!README.md\n*.md\n' 'README.md' ignored
check 'a?c\n' 'abc' ignored
check 'a?c\n' 'a/c' kept
check 'src/*.js\n' 'src/a/b.js' kept
check '**/gen\n' 'gen' ignored
check '**/gen\n' 'a/b/gen' ignored
check 'out/**\n' 'out/a/b' ignored
check 'out/**\n' 'out' kept
check 'a/**/b\n' 'a/b' ignored
check 'a/**/b\n' 'a/x/y/b' ignored
check 'a/**/b\n' 'a/x/c' kept
check 'a[1].txt\n' 'a[1].txt' ignored
check 'a[1].txt\n' 'a1.txt' kept
check 'a.b\n' 'axb' kept

# filter modes
printf '*.lock\n' > "$TMP/.devlogignore"
OUT="$(printf '%s\n' ' M a.txt' ' M x.lock' 'R  old.txt -> new.lock' '?? gen/' | devlog_ignore_filter "$TMP" status)"
[ "$OUT" = " M a.txt
?? gen/" ] && echo "PASS: status mode + rename new path" || { echo "FAIL: status mode: $OUT"; FAIL=1; }
OUT="$(printf 'M\ta.txt\nA\tb.lock\n' | devlog_ignore_filter "$TMP" tab)"
[ "$OUT" = "$(printf 'M\ta.txt')" ] && echo "PASS: tab mode" || { echo "FAIL: tab mode: $OUT"; FAIL=1; }

# untracked dir entry treated as directory
printf 'gen/\n' > "$TMP/.devlogignore"
devlog_ignored "$TMP" 'gen/' && echo "PASS: dir entry ignored" || { echo "FAIL: dir entry"; FAIL=1; }

# fail-open: no file, unreadable file, garbage
rm -f "$TMP/.devlogignore"
OUT="$(printf 'a\nb\n' | devlog_ignore_filter "$TMP")"; rc=$?
[ "$OUT" = "$(printf 'a\nb')" ] && [ $rc -eq 0 ] && echo "PASS: no file passthrough" || { echo "FAIL: no file"; FAIL=1; }
printf '\377\376(((\n[\n\\\n**\n' > "$TMP/.devlogignore"
OUT="$(printf 'a\n' | devlog_ignore_filter "$TMP")"; rc=$?
[ "$OUT" = "a" ] && [ $rc -eq 0 ] && echo "PASS: garbage file fail-open" || { echo "FAIL: garbage: $OUT rc=$rc"; FAIL=1; }
mkdir "$TMP/d2"; mkdir "$TMP/d2/.devlogignore"
OUT="$(printf 'a\n' | devlog_ignore_filter "$TMP/d2")"
[ "$OUT" = "a" ] && echo "PASS: directory-as-file fail-open" || { echo "FAIL: dir-as-file"; FAIL=1; }

exit $FAIL
