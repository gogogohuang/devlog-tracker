# One pass over one devlog file for report-devlog.sh
# (docs/design/read-side-and-promote.md B). POSIX awk only (mawk / BSD awk).
# Vars: branch, label (file leaf name), with_input (0|1).
# Emits one line per block:
#   R<TAB>status<TAB>at<TAB>branch<TAB>round-json
#   C<TAB>branch<TAB>checkpoint-json
# Headings inside ``` fences are content, not structure (same rule as
# devlog-md.sh).
BEGIN {
  # Build the 0x01-0x1F control bytes once; \t \r \n get their short escapes
  # below, the rest (e.g. pasted ANSI \033) fall back to \u00XX.
  for (ci = 1; ci <= 31; ci++) { cchar[ci] = sprintf("%c", ci); cesc[ci] = sprintf("\\u%04x", ci) }
}
function esc(s,    ci) {
  gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
  gsub(/\t/, "\\t", s); gsub(/\r/, "\\r", s); gsub(/\n/, "\\n", s)
  for (ci = 1; ci <= 31; ci++) if (index(s, cchar[ci]) > 0) gsub(cchar[ci], cesc[ci], s)
  return s
}
function trim_nl(s) { sub(/^\n+/, "", s); sub(/\n+$/, "", s); return s }
function flush_section() {
  if (sec == "") return
  if (sec == "segment") segs[nseg++] = trim_nl(buf)
  else part[sec] = trim_nl(buf)
  sec = ""; buf = ""
}
function flush_block(   i, st, js) {
  flush_section()
  if (kind == "round") {
    st = part["status"]; sub(/\n.*/, "", st); gsub(/[ \t`*]/, "", st)
    if (st !~ /^(DONE|IN_PROGRESS|BLOCKED|INTERRUPTED)$/) st = ""
    js = "{\"branch\":\"" esc(branch) "\",\"file\":\"" esc(label) "\",\"line\":" rline ",\"n\":" rn
    js = js ",\"at\":\"" esc(at) "\",\"status\":\"" st "\""
    js = js ",\"summary\":\"" esc(part["summary"]) "\",\"reply\":\"" esc(part["reply"]) "\""
    js = js ",\"handoff\":\"" esc(part["handoff"]) "\",\"segments\":["
    for (i = 0; i < nseg; i++) js = js (i ? "," : "") "\"" esc(segs[i]) "\""
    js = js "]"
    if (with_input) js = js ",\"input\":\"" esc(part["input"]) "\""
    js = js "}"
    printf "R\t%s\t%s\t%s\t%s\n", st, at, branch, js
  } else if (kind == "checkpoint") {
    printf "C\t%s\t{\"branch\":\"%s\",\"file\":\"%s\",\"line\":%d,\"heading\":\"%s\",\"body\":\"%s\"}\n", \
      branch, esc(branch), esc(label), cline, esc(cheading), esc(trim_nl(buf_cp))
  }
  kind = ""; split("", part); split("", segs); nseg = 0; buf_cp = ""
}
/^[ \t]*```/ { fence = !fence }
!fence && /^## / {
  flush_block()
  if ($0 ~ /^## Round [0-9]+/) {
    kind = "round"; rline = NR
    rn = $0; sub(/^## Round /, "", rn); sub(/[^0-9].*$/, "", rn)
    at = ""
    if (index($0, "— ")) at = substr($0, index($0, "— ") + length("— "))
  } else if ($0 ~ /^## Checkpoint/) {
    kind = "checkpoint"; cline = NR; cheading = substr($0, 4)
  }
  next
}
kind == "checkpoint" { buf_cp = buf_cp $0 "\n"; next }
kind == "round" && !fence && /^### / {
  flush_section()
  h = substr($0, 5)
  if (h ~ /^User Input[ \t]*$/) sec = "input"
  else if (h ~ /^Summary[ \t]*$/) sec = "summary"
  else if (h ~ /^Reply[ \t]*$/) sec = "reply"
  else if (h ~ /^Handoff[ \t]*$/) sec = "handoff"
  else if (h ~ /^Status[ \t]*$/) sec = "status"
  else if (h ~ /^段落 /) { sec = "segment"; buf = h "\n"; next }
  else sec = "other"
  next
}
kind == "round" && sec != "" { buf = buf $0 "\n" }
END { flush_block() }
