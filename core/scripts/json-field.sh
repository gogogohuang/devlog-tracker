# shellcheck shell=bash
# sourced by hook scripts. Do not execute.
json_int_get() {
  local file="$1" key="$2" raw=""
  [ -f "$file" ] || { echo ''; return 0; }
  # Read digits from the file text first so leading-zero values like 08
  # stay visible (jq would coerce them and bash would treat them as octal).
  raw="$(grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[0-9]\+" "$file" 2>/dev/null | grep -o '[0-9]\+$' || echo '')"
  if [ -z "$raw" ] && command -v jq >/dev/null 2>&1; then
    raw="$(jq -r --arg k "$key" '.[$k] | tostring' "$file" 2>/dev/null || echo '')"
    [ "$raw" = "null" ] && raw=""
  fi
  case "$raw" in
    ''|*[!0-9]*) echo ''; return 0 ;;
    0) echo 0; return 0 ;;
    0*) echo ''; return 0 ;;
    *) echo "$raw"; return 0 ;;
  esac
}

json_str_get() {
  local file="$1" key="$2" raw=""
  [ -f "$file" ] || { echo ''; return 0; }
  if command -v jq >/dev/null 2>&1; then
    raw="$(jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || echo '')"
    [ "$raw" = "null" ] && raw=""
    printf '%s' "$raw"
    echo
    return 0
  fi
  raw="$(grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -1 || echo '')"
  printf '%s' "$raw" | sed -E "s/^.*\"${key}\"[[:space:]]*:[[:space:]]*\"//; s/\"$//"
  echo
}

json_int_set() {
  local file="$1" key="$2" val="$3"
  [ -f "$file" ] || return 0
  case "$val" in ''|*[!0-9]*) return 0 ;; esac
  awk -v key="$key" -v val="$val" '{
    pat = "\"" key "\"[[:space:]]*:[[:space:]]*[0-9]+"
    repl = "\"" key "\": " val
    gsub(pat, repl)
    print
  }' "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null || true
}

json_str_set() {
  local file="$1" key="$2" val="$3"
  [ -f "$file" ] || return 0
  case "$val" in *\"*|*[$'\n']*) return 0 ;; esac
  awk -v key="$key" -v val="$val" '{
    pat = "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\""
    repl = "\"" key "\": \"" val "\""
    gsub(pat, repl)
    print
  }' "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null || true
}

json_str_field() {
  local json="$1" key="$2" raw=""
  if command -v jq >/dev/null 2>&1; then
    raw="$(printf '%s' "$json" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null || echo '')"
    [ "$raw" = "null" ] && raw=""
    printf '%s' "$raw"
    echo
    return 0
  fi
  # 值要吃得下 \" 這類跳脫序列，否則含引號的 prompt 會在第一個 \" 被截斷；
  # 抓出來之後再還原 \n \t \r \" \\ \/（\uXXXX 不處理，原樣保留）。
  local pat='"'"${key}"'"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"'
  raw="$(printf '%s' "$json" | grep -oE "$pat" 2>/dev/null | head -1 || echo '')"
  printf '%s' "$raw" | sed -E "s/^\"${key}\"[[:space:]]*:[[:space:]]*\"//; s/\"$//" | awk '
    BEGIN { ORS = "" }
    {
      s = $0; out = ""
      while (length(s) > 0) {
        c = substr(s, 1, 1)
        if (c == "\\" && length(s) > 1) {
          n = substr(s, 2, 1)
          if (n == "n") out = out "\n"
          else if (n == "t") out = out "\t"
          else if (n == "r") out = out "\r"
          else if (n == "u") out = out "\\u"
          else out = out n
          s = substr(s, 3)
        } else { out = out c; s = substr(s, 2) }
      }
      print out
    }'
  echo
}

slugify() {
  printf '%s' "$1" | tr ' ' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//'
}

json_escape() {
  printf '%s' "$1" | awk '
    BEGIN {
      ORS = ""
      # Same control-char handling as report-scan.awk esc(): \t \r get short
      # escapes below, the rest of 0x01-0x1F (e.g. pasted ANSI \033) -> \u00XX.
      for (ci = 1; ci <= 31; ci++) { cchar[ci] = sprintf("%c", ci); cesc[ci] = sprintf("\\u%04x", ci) }
    }
    {
      gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r")
      for (ci = 1; ci <= 31; ci++) if (index($0, cchar[ci]) > 0) gsub(cchar[ci], cesc[ci])
      if (NR > 1) print "\\n"
      print
    }'
}
