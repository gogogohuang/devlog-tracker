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
  raw="$(printf '%s' "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" 2>/dev/null | head -1 || echo '')"
  printf '%s' "$raw" | sed -E "s/^.*\"${key}\"[[:space:]]*:[[:space:]]*\"//; s/\"$//"
  echo
}

slugify() {
  printf '%s' "$1" | tr ' ' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//'
}
