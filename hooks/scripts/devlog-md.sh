#!/usr/bin/env bash

devlog_list_round_starts() {
  awk '
    /^[ \t]*```/ { fence = !fence; next }
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
    /^[ \t]*```/ { fence = !fence }
    NR > start && !fence && /^## / { print NR - 1; found = 1; exit }
    END { if (!found) print NR }
  ' "$1"
}

devlog_round_status() {
  awk -v start="$2" -v end="$3" '
    NR < start || NR > end { next }
    /^[ \t]*```/ { fence = !fence; next }
    !fence && /^### Status[[:space:]]*$/ { status = 1; value = ""; next }
    !fence && /^### / && status { status = 0 }
    status && $0 !~ /^[[:space:]]*$/ { value = $0 }
    END { print value }
  ' "$1"
}

devlog_count_segments() {
  awk -v start="$2" -v end="$3" '
    NR < start || NR > end { next }
    /^[ \t]*```/ { fence = !fence; next }
    !fence && /^### 段落 / { count++ }
    END { print count + 0 }
  ' "$1"
}

devlog_insert_before_summary() {
  local file="$1" start="$2" end="$3" text_file="$4"
  awk -v start="$start" -v end="$end" -v textfile="$text_file" '
    BEGIN {
      inserted = 0
      while ((getline line < textfile) > 0) {
        ins[ni++] = line
      }
      close(textfile)
    }
    {
      if (!inserted && NR >= start && NR <= end && !fence && $0 ~ /^### Summary[[:space:]]*$/) {
        for (i = 0; i < ni; i++) print ins[i]
        inserted = 1
      }
    if ($0 ~ /^[ \t]*```/) fence = !fence
    print
  }
  ' "$file"
}

devlog_kept_index_lines() {
  awk '
    /^[ \t]*```/ { fence = !fence; next }
    !fence && /^## Kept 索引/ { grab = 1; found = 1; buf = ""; next }
    !fence && grab && /^## / { grab = 0 }
    grab { buf = buf $0 ORS }
    END { if (found) printf "%s", buf }
  ' "$1"
}

devlog_strip_kept_index() {
  awk '
    /^[ \t]*```/ { fence = !fence }
    !fence && /^## Kept 索引/ { grab = 1; next }
    !fence && grab && /^## / { grab = 0 }
    grab { next }
    { print }
  ' "$1" > "$2"
}
