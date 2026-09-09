#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
mkdir -p "$TMP/.devlog"
FAIL=0
assert_eq() {
  local d="$1" e="$2" a="$3"
  if [ "$e" = "$a" ]; then echo "PASS: $d"; else echo "FAIL: $d expected [$e] got [$a]"; FAIL=1; fi
}

bash "$SCRIPT_DIR/compact-devlog.sh" >/dev/null
assert_eq "missing log exit 1" "1" "$?"

round() {
  local n="$1" st="$2"
  cat >> "$TMP/.devlog/devlog.md" <<EOF
## Round ${n} — 2026-09-09T12:00:00+08:00

### Summary
s${n}

### Handoff
#### 現況
h${n}

### Status
${st}
EOF
}

: > "$TMP/.devlog/devlog.md"
printf '%s\n\n' '# preamble' >> "$TMP/.devlog/devlog.md"
n=1
while [ "$n" -le 8 ]; do round "$n" DONE; n=$((n+1)); done
round 9 IN_PROGRESS
cat >> "$TMP/.devlog/devlog.md" <<'EOF'
## Checkpoint（Round 1-3 摘要）
cp body
EOF

OUT="$(bash "$SCRIPT_DIR/compact-devlog.sh")"
assert_eq "compact exit 0" "0" "$?"
echo "$OUT" | grep -q 'MOVED=3' && echo "PASS: moved 1-3" || { echo "FAIL: $OUT"; FAIL=1; }
grep -q '# preamble' "$TMP/.devlog/devlog.md" && echo "PASS: preamble stays" || { echo "FAIL: preamble"; FAIL=1; }
grep -q '## Checkpoint' "$TMP/.devlog/devlog.md" && echo "PASS: checkpoint stays" || { echo "FAIL: cp"; FAIL=1; }
grep -q '## Round 9' "$TMP/.devlog/devlog.md" && echo "PASS: in-progress stays" || { echo "FAIL: r9"; FAIL=1; }
grep -q '## Round 4' "$TMP/.devlog/devlog.md" && echo "PASS: last-5 keep 4" || { echo "FAIL: r4"; FAIL=1; }
grep -q '## Round 1' "$TMP/.devlog/devlog.archive.md" && echo "PASS: archive has 1" || { echo "FAIL: archive"; FAIL=1; }
grep -q '## Round 9' "$TMP/.devlog/devlog.archive.md" && { echo "FAIL: archived in-progress"; FAIL=1; } || echo "PASS: did not archive 9"
test -f "$TMP/.devlog/devlog.foo.md" && { echo "FAIL: touched keep file"; FAIL=1; } || echo "PASS: no keep file"

OUT2="$(bash "$SCRIPT_DIR/compact-devlog.sh")"
echo "$OUT2" | grep -q 'MOVED=0' && echo "PASS: second compact moves 0" || { echo "FAIL: $OUT2"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
