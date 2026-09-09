#!/usr/bin/env bash

devlog_list_round_starts() {
  awk '
    /^```/ { fence = !fence; next }
    !fence && /^## Round [0-9]+/ {
      round = $0
      sub(/^## Round /, "", round)
      sub(/[^0-9].*$/, "", round)
      print NR, round
    }
  ' "$1"
}

devlog_block_end() {
  awk -v start="$2" '
    NR < start { next }
    /^```/ { fence = !fence }
    NR > start && !fence && /^## / { print NR - 1; found = 1; exit }
    END { if (!found) print NR }
  ' "$1"
}

devlog_round_status() {
  awk -v start="$2" -v end="$3" '
    NR < start || NR > end { next }
    /^```/ { fence = !fence; next }
    !fence && /^### Status[[:space:]]*$/ { status = 1; value = ""; next }
    !fence && /^### / && status { status = 0 }
    status && $0 !~ /^[[:space:]]*$/ { value = $0 }
    END { print value }
  ' "$1"
}
