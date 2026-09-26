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
