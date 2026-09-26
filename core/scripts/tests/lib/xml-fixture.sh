#!/usr/bin/env bash
# Test helper: convert a legacy-format fixture file to XML in place.
_XML_FIXTURE_DIR="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
# shellcheck source=../../handoff-convert.sh
. "$_XML_FIXTURE_DIR/handoff-convert.sh"
xml_fixture() {
  local f="$1"
  handoff_convert_file "$f" "$f.xml" "$f.xmlrep" && mv "$f.xml" "$f"
  rm -f "$f.xmlrep"
}

# TRANSITIONAL (handoff-xml Task 4 → Task 5): convert only ### Handoff and
# leave ### Session Handoff legacy, because the Stop hook's Session Handoff
# check still expects `#### ` until Task 5. Task 5 replaces every call with
# xml_fixture and deletes this function.
xml_fixture_handoff_only() {
  local f="$1"
  sed -e 's/^### Session Handoff[[:space:]]*$/### __XML_FIXTURE_SESSION__/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  xml_fixture "$f"
  sed -e 's/^### __XML_FIXTURE_SESSION__$/### Session Handoff/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
