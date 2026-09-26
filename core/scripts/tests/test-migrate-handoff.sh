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

[ "$FAIL" -eq 0 ] || exit 1
echo "All migrate-handoff checks passed."
