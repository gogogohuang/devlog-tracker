#!/usr/bin/env bash
# Self-check for handoff-fields.sh (docs/design/handoff-xml.md).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../handoff-fields.sh
. "$SCRIPT_DIR/handoff-fields.sh"
FAIL=0
eq() {
  if [ "$2" = "$3" ]; then echo "PASS: $1"; else printf 'FAIL: %s\n--- expected\n%s\n--- actual\n%s\n' "$1" "$2" "$3"; FAIL=1; fi
}
check_fails() {
  local desc="$1" body="$2" kind="$3" want="$4" out
  if out="$(handoff_xml_check "$body" "$kind")"; then
    echo "FAIL: $desc (expected check to fail)"; FAIL=1; return
  fi
  case "$out" in
    *"$want"*) echo "PASS: $desc" ;;
    *) echo "FAIL: $desc (message lacks '$want': $out)"; FAIL=1 ;;
  esac
}

XML='
<handoff>
<decisions>
pick A
</decisions>
<workspace>
main @ abc1234，工作樹乾淨
</workspace>
<next>
edit `core/scripts/x.sh`
```sh
### not a heading
```
</next>
</handoff>
'
MD='
#### 決策
pick A
#### 工作區
main @ abc1234，工作樹乾淨
#### 下一步
edit `core/scripts/x.sh`
'

eq "format xml" xml "$(handoff_format "$XML")"
eq "format md" md "$(handoff_format "$MD")"
eq "format none" none "$(handoff_format 'just prose')"
eq "xml field decisions" "pick A" "$(handoff_field "$XML" decisions)"
eq "xml field workspace" "main @ abc1234，工作樹乾淨" "$(handoff_field "$XML" workspace)"
eq "xml field keeps fenced content" 'edit `core/scripts/x.sh`
```sh
### not a heading
```' "$(handoff_field "$XML" next)"
eq "xml missing field empty" "" "$(handoff_field "$XML" state)"
eq "md field workspace" "main @ abc1234，工作樹乾淨" "$(handoff_field "$MD" workspace)"
eq "md field next" 'edit `core/scripts/x.sh`' "$(handoff_field "$MD" next)"
eq "md heading exact match only" "" "$(handoff_field '#### 工作區（舊）
x' workspace)"
eq "md fenced heading ignored" "" "$(handoff_field '```
#### 工作區
fake
```' workspace)"

if handoff_xml_check "$XML" handoff >/dev/null; then echo "PASS: valid xml passes"; else echo "FAIL: valid xml"; FAIL=1; fi
check_fails "must open with tag" 'prose
<handoff>
</handoff>' handoff "<handoff>"
check_fails "text after block" '<handoff>
<state>
x
</state>
</handoff>
trailing' handoff "外面"
check_fails "unknown tag" '<handoff>
<done_when>
x
</done_when>
</handoff>' handoff "done_when"
check_fails "inline tag" '<handoff>
<next>做 X</next>
</handoff>' handoff "自己一行"
check_fails "unclosed field" '<handoff>
<state>
x
</handoff>' handoff "</state>"
check_fails "missing block close" '<handoff>
<state>
x
</state>' handoff "</handoff>"
check_fails "duplicate" '<handoff>
<state>
x
</state>
<state>
y
</state>
</handoff>' handoff "超過一次"
check_fails "order" '<handoff>
<next>
x
</next>
<state>
y
</state>
</handoff>' handoff "順序"
check_fails "empty field" '<handoff>
<state>
</state>
</handoff>' handoff "是空的"
check_fails "session requires all three" '<session-handoff>
<decisions>
- （無）
</decisions>
</session-handoff>' session-handoff "open-questions"
check_fails "session tag not allowed in handoff" '<handoff>
<open-questions>
x
</open-questions>
</handoff>' handoff "open-questions"

ROUND='## Round 1 — t

### Handoff
<handoff>
<state>
s
</state>
</handoff>

### Session Handoff
<session-handoff>
<decisions>
- d
</decisions>
</session-handoff>

### Status
DONE'
eq "section_of Handoff" "<handoff>
<state>
s
</state>
</handoff>" "$(handoff_section_of "$ROUND" Handoff | awk 'NF')"
eq "section_of Session Handoff" "<session-handoff>
<decisions>
- d
</decisions>
</session-handoff>" "$(handoff_section_of "$ROUND" 'Session Handoff' | awk 'NF')"

SKILL="$(cat "$SCRIPT_DIR/../../skills/devlog-tracker/SKILL.md")"
for kind in handoff session-handoff; do
  case "$SKILL" in
    *"$(handoff_xml_template "$kind")"*) echo "PASS: SKILL.md carries $kind template" ;;
    *) echo "FAIL: SKILL.md template for $kind differs from handoff_xml_template"; FAIL=1 ;;
  esac
done

MSG="$(handoff_legacy_message /abs/core/scripts/migrate-handoff.sh /abs/proj)"
case "$MSG" in
  *'DEVLOG_PROJECT_DIR="/abs/proj" bash "/abs/core/scripts/migrate-handoff.sh"'*) echo "PASS: legacy message has migrate command" ;;
  *) echo "FAIL: legacy message lacks migrate command: $MSG"; FAIL=1 ;;
esac
case "$MSG" in
  *"npx devlog-tracker init"*"/devlog-tracker:start"*) echo "PASS: legacy message has init/start hint" ;;
  *) echo "FAIL: legacy message lacks init/start hint"; FAIL=1 ;;
esac

[ "$FAIL" -eq 0 ] || exit 1
echo "All handoff-fields checks passed."
