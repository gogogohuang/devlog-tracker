#!/usr/bin/env bash
# Self-check for handoff-convert.sh + migrate-handoff.sh (docs/design/handoff-xml.md).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../handoff-convert.sh
. "$SCRIPT_DIR/handoff-convert.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
eq() {
  if [ "$2" = "$3" ]; then echo "PASS: $1"; else printf 'FAIL: %s\n--- expected\n%s\n--- actual\n%s\n' "$1" "$2" "$3"; FAIL=1; fi
}

cat > "$TMP/in.md" <<'EOF'
# Project

## Round 1 — t1

### Summary
s1

### Handoff
#### 決策
pick A

#### 工作區
main @ abc1234，工作樹乾淨
#### 下一步
run `x`
```
#### 下一步
fenced, not a heading
```

### Session Handoff

#### 決策
- （無）

#### 待解問題
- q

#### 失敗嘗試
- （無）

### Status
IN_PROGRESS

## Checkpoint（Round 1-1 摘要）
### 決策
untouched

## Round 2 — t2

### Handoff
#### 自訂小節
x

### Status
DONE

## Round 3 — t3

### Handoff
<handoff>
<state>
already xml
</state>
</handoff>

### Status
DONE
EOF

cat > "$TMP/want.md" <<'EOF'
# Project

## Round 1 — t1

### Summary
s1

### Handoff
<handoff>
<decisions>
pick A
</decisions>
<workspace>
main @ abc1234，工作樹乾淨
</workspace>
<next>
run `x`
```
#### 下一步
fenced, not a heading
```
</next>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- （無）
</decisions>
<open-questions>
- q
</open-questions>
<failed-attempts>
- （無）
</failed-attempts>
</session-handoff>

### Status
IN_PROGRESS

## Checkpoint（Round 1-1 摘要）
### 決策
untouched

## Round 2 — t2

### Handoff
#### 自訂小節
x

### Status
DONE

## Round 3 — t3

### Handoff
<handoff>
<state>
already xml
</state>
</handoff>

### Status
DONE
EOF

handoff_convert_file "$TMP/in.md" "$TMP/out.md" "$TMP/report"
eq "convert output" "$(cat "$TMP/want.md")" "$(cat "$TMP/out.md")"
eq "report" "MIGRATED 1
SKIP 2 不認得的小節「#### 自訂小節」" "$(cat "$TMP/report")"

handoff_convert_file "$TMP/out.md" "$TMP/out2.md" "$TMP/report2"
eq "idempotent output" "$(cat "$TMP/out.md")" "$(cat "$TMP/out2.md")"
eq "idempotent report only repeats skip" "SKIP 2 不認得的小節「#### 自訂小節」" "$(cat "$TMP/report2")"

printf '## Round 4 — t\n\n### Handoff\n#### 現況\na\n#### 決策\nb\n' > "$TMP/order.md"
handoff_convert_file "$TMP/order.md" "$TMP/order.out" "$TMP/order.rep"
eq "bad order untouched" "$(cat "$TMP/order.md")" "$(cat "$TMP/order.out")"
case "$(cat "$TMP/order.rep")" in SKIP\ 4\ *) echo "PASS: bad order reported" ;; *) echo "FAIL: bad order report"; FAIL=1 ;; esac

printf '## Round 5 — t\n\n### Handoff\n#### 現況\n```\nunclosed\n' > "$TMP/fence.md"
handoff_convert_file "$TMP/fence.md" "$TMP/fence.out" "$TMP/fence.rep"
eq "odd fence untouched" "$(cat "$TMP/fence.md")" "$(cat "$TMP/fence.out")"

printf '## Session Handoff\n\n### 決策\n- a\n\n### 待解問題\n- b\n\n### 失敗嘗試\n- （無）\n' > "$TMP/h.md"
handoff_convert_snapshot "$TMP/h.md" "$TMP/h.out"; RC=$?
eq "snapshot rc" 0 "$RC"
eq "snapshot xml" "<session-handoff>
<decisions>
- a
</decisions>
<open-questions>
- b
</open-questions>
<failed-attempts>
- （無）
</failed-attempts>
</session-handoff>" "$(cat "$TMP/h.out")"
handoff_convert_snapshot "$TMP/h.out" "$TMP/h.out2"; RC=$?
eq "snapshot already xml rc" 2 "$RC"

# ---- migrate-handoff.sh (Task 3 appends below this line) ----

P="$TMP/proj"; D="$P/.devlog"; mkdir -p "$D"
cp "$TMP/in.md" "$D/devlog.md"
{ printf '<!-- devlog-origin: branch=feat/x -->\n\n'; cat "$TMP/in.md"; } > "$D/devlog.feat-x.md"
cp "$TMP/in.md" "$D/devlog.archive.md"
cp "$TMP/in.md" "$D/devlog.mytopic.md"
cp "$TMP/h.md" "$D/handoff.md"
OUT="$(DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/migrate-handoff.sh")"; RC=$?
eq "migrate rc" 0 "$RC"
case "$OUT" in *"MIGRATED=2"*) echo "PASS: migrated count (main + branch)" ;; *) echo "FAIL: migrated count: $OUT"; FAIL=1 ;; esac
case "$OUT" in *"SKIP devlog.md Round 2: "*) echo "PASS: skip line" ;; *) echo "FAIL: skip line: $OUT"; FAIL=1 ;; esac
eq "main converted" "$(cat "$TMP/want.md")" "$(cat "$D/devlog.md")"
eq "backup kept original" "$(cat "$TMP/in.md")" "$(cat "$D/devlog.md.pre-migrate")"
grep -q '^<handoff>$' "$D/devlog.feat-x.md" && echo "PASS: branch file converted" || { echo "FAIL: branch file"; FAIL=1; }
eq "archive untouched" "$(cat "$TMP/in.md")" "$(cat "$D/devlog.archive.md")"
eq "keep file untouched" "$(cat "$TMP/in.md")" "$(cat "$D/devlog.mytopic.md")"
grep -q '^<session-handoff>$' "$D/handoff.md" && echo "PASS: handoff.md converted" || { echo "FAIL: handoff.md"; FAIL=1; }
OUT2="$(DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/migrate-handoff.sh")"
case "$OUT2" in *"MIGRATED=0"*) echo "PASS: second run migrates nothing" ;; *) echo "FAIL: second run: $OUT2"; FAIL=1 ;; esac
[ ! -d "$D/.lock" ] && echo "PASS: lock released" || { echo "FAIL: lock left behind"; FAIL=1; }
OUT3="$(DEVLOG_PROJECT_DIR="$TMP/nope" bash "$SCRIPT_DIR/migrate-handoff.sh")"; RC=$?
eq "no devlog rc" 1 "$RC"
eq "no devlog out" "NO_DEVLOG" "$OUT3"

# Coverage gap 1: a duplicated `#### 現況` inside one Handoff leaves that
# round byte-for-byte untouched and is reported as SKIP mentioning 重複.
printf '## Round 10 — dup\n\n### Handoff\n#### 現況\na\n#### 現況\nb\n\n### Status\nIN_PROGRESS\n' > "$TMP/dup.md"
handoff_convert_file "$TMP/dup.md" "$TMP/dup.out" "$TMP/dup.rep"
eq "duplicate section untouched" "$(cat "$TMP/dup.md")" "$(cat "$TMP/dup.out")"
case "$(cat "$TMP/dup.rep")" in SKIP\ 10\ *重複*) echo "PASS: duplicate section reported" ;; *) echo "FAIL: duplicate section report: $(cat "$TMP/dup.rep")"; FAIL=1 ;; esac

# Coverage gap 2: Handoff is valid legacy but Session Handoff has an unknown
# `#### 其他` subsection — the WHOLE round (including the convertible
# Handoff) is left byte-for-byte untouched and reported SKIP.
printf '## Round 11 — mixed\n\n### Handoff\n#### 決策\npick\n\n### Session Handoff\n#### 其他\nx\n\n### Status\nDONE\n' > "$TMP/mixed.md"
handoff_convert_file "$TMP/mixed.md" "$TMP/mixed.out" "$TMP/mixed.rep"
eq "unknown session-handoff subsection leaves whole round untouched" "$(cat "$TMP/mixed.md")" "$(cat "$TMP/mixed.out")"
case "$(cat "$TMP/mixed.rep")" in SKIP\ 11\ *) echo "PASS: mixed round skipped" ;; *) echo "FAIL: mixed round report: $(cat "$TMP/mixed.rep")"; FAIL=1 ;; esac

# Odd fence (a): the open round's User Input pasted an unbalanced fence (3
# ``` lines). Stop's NOFENCE gate still sees the legacy Handoff, so migrate
# must report it SKIP instead of silently finding nothing.
P2="$TMP/proj-odd"; D2="$P2/.devlog"; mkdir -p "$D2"
printf '## Round 7 — t\n\n### User Input\npaste:\n```\ncode\n```\n```\nunclosed\n\n### Summary\ns\n\n### Reply\nr\n\n### Handoff\n#### 現況\na\n\n#### 下一步\nb\n' > "$D2/.round-current.md"
cp "$D2/.round-current.md" "$TMP/odd-a.orig"
OUT4="$(DEVLOG_PROJECT_DIR="$P2" bash "$SCRIPT_DIR/migrate-handoff.sh")"
case "$OUT4" in *"SKIP .round-current.md Round 7: fence 沒有成對"*) echo "PASS: odd fence in open round reported SKIP" ;; *) echo "FAIL: odd fence open round: $OUT4"; FAIL=1 ;; esac
case "$OUT4" in *"SKIPPED=1"*) echo "PASS: odd fence open round counted" ;; *) echo "FAIL: odd fence open round count: $OUT4"; FAIL=1 ;; esac
eq "odd fence open round untouched" "$(cat "$TMP/odd-a.orig")" "$(cat "$D2/.round-current.md")"

# Odd fence (b): an unbalanced fence in an old round's Summary must not
# swallow every later `## Round` heading.
printf '## Round 1 — old\n\n### Summary\n```\nunclosed\n\n### Handoff\n#### 現況\na\n\n### Status\nDONE\n\n## Round 2 — new\n\n### Handoff\n#### 現況\nb\n\n### Status\nDONE\n' > "$TMP/odd-b.md"
handoff_convert_file "$TMP/odd-b.md" "$TMP/odd-b.out" "$TMP/odd-b.rep"
eq "odd fence (b) report" "SKIP 1 fence 沒有成對
MIGRATED 2" "$(cat "$TMP/odd-b.rep")"
eq "odd fence (b) output" "## Round 1 — old

### Summary
\`\`\`
unclosed

### Handoff
#### 現況
a

### Status
DONE

## Round 2 — new

### Handoff
<handoff>
<state>
b
</state>
</handoff>

### Status
DONE" "$(cat "$TMP/odd-b.out")"

# migrate_snapshot_file rc=1: an unrecognised handoff.md is reported, untouched.
P3="$TMP/proj-snap"; D3="$P3/.devlog"; mkdir -p "$D3"
printf 'random notes\n' > "$D3/handoff.md"
OUT5="$(DEVLOG_PROJECT_DIR="$P3" bash "$SCRIPT_DIR/migrate-handoff.sh")"
case "$OUT5" in *"SKIP handoff.md: "*) echo "PASS: unknown snapshot reported" ;; *) echo "FAIL: unknown snapshot: $OUT5"; FAIL=1 ;; esac
eq "unknown snapshot untouched" "random notes" "$(cat "$D3/handoff.md")"

# Branch file from before the devlog-origin marker existed: still migrated
# when that branch is checked out (resolved via devlog_resolve_paths).
P4="$TMP/proj-git"; D4="$P4/.devlog"; mkdir -p "$D4"
git -C "$P4" init -q
git -C "$P4" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$P4" checkout -q -b feat/y
cp "$TMP/in.md" "$D4/devlog.feat-y.md"
OUT6="$(DEVLOG_PROJECT_DIR="$P4" bash "$SCRIPT_DIR/migrate-handoff.sh")"
eq "markerless current branch file converted" "$(cat "$TMP/want.md")" "$(cat "$D4/devlog.feat-y.md")"
case "$OUT6" in *"MIGRATED=1"*) echo "PASS: markerless branch file converted once" ;; *) echo "FAIL: markerless branch count: $OUT6"; FAIL=1 ;; esac

[ "$FAIL" -eq 0 ] || exit 1
echo "All migrate-handoff checks passed."
