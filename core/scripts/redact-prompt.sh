#!/usr/bin/env bash
# Sourced helper: redact_prompt reads stdin and writes sanitized prompt text.
redact_prompt() {
  awk '
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/ { skip=1; print "（已遮罩）"; next }
    skip && /-----END [A-Z ]*PRIVATE KEY-----/ { skip=0; next }
    skip { next }
    { print }
  ' | sed -E \
    -e 's/sk-ant-api03-[A-Za-z0-9_-]+/（已遮罩）/g' \
    -e 's/sk-ant-[A-Za-z0-9_-]{20,}/（已遮罩）/g' \
    -e 's/sk-[A-Za-z0-9]{20,}/（已遮罩）/g' \
    -e 's/ghp_[A-Za-z0-9]{20,}/（已遮罩）/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/（已遮罩）/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/（已遮罩）/g' \
    -e 's/AKIA[A-Z0-9]{16}/（已遮罩）/g' \
    -e 's/Bearer [A-Za-z0-9._+=/-]{20,}/（已遮罩）/g' \
    -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/（已遮罩）/g'
}
