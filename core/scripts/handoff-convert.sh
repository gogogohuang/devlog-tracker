#!/usr/bin/env bash
# Sourced helper: legacy `#### ` Handoff → line-based XML. Pure file-in /
# file-out; locking, backups and target discovery live in
# migrate-handoff.sh. Converts history as-is: never validates, fills or
# drops fields; a round it cannot map exactly is left byte-for-byte.
# docs/design/handoff-xml.md「Migrate」.

_HANDOFF_CONVERT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=handoff-fields.sh
. "$_HANDOFF_CONVERT_DIR/handoff-fields.sh"

_handoff_convert_awk() {
  # Heading → tag tables are generated from handoff-fields.sh so the map
  # lives in one place.
  local hmap="" smap="" k
  for k in $HANDOFF_KEYS; do hmap="$hmap $(handoff_key_heading "$k")=$k"; done
  for k in $SESSION_HANDOFF_KEYS; do smap="$smap $(handoff_key_heading "$k")=$k"; done
  awk -v hmap="$hmap" -v smap="$smap" -v report="$1" '
    function load(map, dst,   n, i, p, kv) {
      n = split(map, p, " ")
      for (i = 1; i <= n; i++) { split(p[i], kv, "="); dst[kv[1]] = kv[2]; dst["#" kv[1]] = i }
    }
    BEGIN { load(hmap, H); load(smap, S) }
    function emit_round(   i) { for (i = 1; i <= rn; i++) print rl[i] }
    # Converts section lines rl[a..b] (after the ### heading) into out[];
    # returns "" on success or a reason. Fills fk/fs/fe (1..nf) and on/out
    # as side effects.
    function conv(a, b, sess,   i, t, name, key, idx, last, fences, nf, j, e, s) {
      fences = 0
      for (i = a; i <= b; i++) if (rl[i] ~ /^[ \t]*```/) fences++
      if (fences % 2) return "fence 沒有成對"
      for (i = a; i <= b; i++) if (rl[i] ~ /[^ \t]/) break
      if (i > b) return "EMPTY"
      t = rl[i]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t == "<handoff>" || t == "<session-handoff>") return "XML"
      nf = 0; last = 0; fence = 0; delete seen
      for (i = a; i <= b; i++) {
        if (rl[i] ~ /^[ \t]*```/) { fence = !fence; if (nf > 0) continue }
        else if (!fence && rl[i] ~ /^#### /) {
          name = rl[i]; sub(/^#### [ \t]*/, "", name); sub(/[ \t]+$/, "", name)
          key = sess ? S[name] : H[name]
          idx = sess ? S["#" name] : H["#" name]
          if (key == "") return "不認得的小節「#### " name "」"
          if (seen[key]) return "小節「#### " name "」重複"
          if (idx < last) return "小節順序不對（#### " name "）"
          seen[key] = 1; last = idx
          nf++; fk[nf] = key; fs[nf] = i + 1; if (nf > 1) fe[nf - 1] = i - 1
          continue
        }
        if (nf == 0 && rl[i] ~ /[^ \t]/) return "第一個 #### 小節前面有內容"
      }
      if (nf == 0) return "沒有 #### 小節"
      fe[nf] = b
      on = 0
      out[++on] = sess ? "<session-handoff>" : "<handoff>"
      for (j = 1; j <= nf; j++) {
        e = fe[j]
        while (e >= fs[j] && rl[e] !~ /[^ \t]/) e--
        s = fs[j]
        while (s <= e && rl[s] !~ /[^ \t]/) s++
        out[++on] = "<" fk[j] ">"
        for (i = s; i <= e; i++) out[++on] = rl[i]
        out[++on] = "</" fk[j] ">"
      }
      out[++on] = sess ? "</session-handoff>" : "</handoff>"
      return ""
    }
    # First non-blank line of rl[a..b]: "EMPTY", "XML" or "" (legacy).
    function kind(a, b,   i, t) {
      for (i = a; i <= b; i++) if (rl[i] ~ /[^ \t]/) break
      if (i > b) return "EMPTY"
      t = rl[i]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      return (t == "<handoff>" || t == "<session-handoff>") ? "XML" : ""
    }
    function flush(   i, t, k, sb, r, conv_any, cur, nof) {
      if (rn == 0) return
      if (!inround) { emit_round(); rn = 0; return }
      # NOFENCE fail-open (same rule as _hf_nofence／enforce-devlog.sh): an
      # odd number of ``` markers in this round means a fence was never
      # closed, so stop tracking fences while locating sections — that is
      # what the Stop gate sees too.
      nof = 0
      for (i = 1; i <= rn; i++) if (rl[i] ~ /^[ \t]*```/) nof = !nof
      # locate ### Handoff / ### Session Handoff sections (fence-aware)
      ns = 0; fence = 0
      for (i = 1; i <= rn; i++) {
        if (rl[i] ~ /^[ \t]*```/) { if (!nof) fence = !fence; continue }
        if (fence) continue
        if (rl[i] ~ /^### /) {
          if (ns && !se[ns]) se[ns] = i - 1
          t = rl[i]; sub(/[ \t]+$/, "", t)
          if (t == "### Handoff" || t == "### Session Handoff") { ns++; sh[ns] = i; ss[ns] = (t == "### Session Handoff"); se[ns] = 0 }
        }
      }
      if (ns && !se[ns]) se[ns] = rn
      if (nof) {
        # Cannot map a round with a broken fence exactly: leave it as-is,
        # but say so when it still carries a legacy Handoff.
        for (k = 1; k <= ns; k++) if (kind(sh[k] + 1, se[k]) == "") {
          print "SKIP " roundno " fence 沒有成對" > report; break
        }
        emit_round(); rn = 0; return
      }
      conv_any = 0
      for (k = 1; k <= ns; k++) {
        # keep trailing blank lines of the section outside the tag block
        sb = se[k]; while (sb > sh[k] && rl[sb] !~ /[^ \t]/) sb--
        r = conv(sh[k] + 1, sb, ss[k])
        if (r == "XML" || r == "EMPTY") { cstart[k] = 0; continue }
        if (r != "") { print "SKIP " roundno " " r > report; emit_round(); rn = 0; delete cstart; return }
        cstart[k] = sh[k]; cend[k] = sb; conv_any = 1
        cn[k] = on; for (i = 1; i <= on; i++) cl[k, i] = out[i]
      }
      cur = 0
      for (i = 1; i <= rn; i++) {
        if (cur && i <= cend[cur]) {
          if (i == cend[cur]) cur = 0
          continue
        }
        for (k = 1; k <= ns; k++) {
          if (cstart[k] && i == cstart[k] + 1) {
            for (j = 1; j <= cn[k]; j++) print cl[k, j]
            if (cend[k] > i) cur = k; else cur = 0
            break
          }
        }
        if (k <= ns && cstart[k] && i == cstart[k] + 1) continue
        print rl[i]
      }
      if (conv_any) print "MIGRATED " roundno > report
      rn = 0; delete cstart
    }
    { L[++nl] = $0; if ($0 ~ /^[ \t]*```/) tf++ }
    END {
      # Round boundaries: fence-aware, except when the whole file has an
      # odd ``` count — then one unclosed fence would swallow every later
      # `## ` heading, so fall back to plain scanning (NOFENCE rule). A
      # round that ends up with an odd count is SKIPped by flush().
      gnf = tf % 2
      for (li = 1; li <= nl; li++) {
        line = L[li]
        if (!gnf && line ~ /^[ \t]*```/) gfence = !gfence
        if (!gfence && line ~ /^## /) {
          flush()
          inround = (line ~ /^## Round [0-9]+/)
          if (inround) { roundno = line; sub(/^## Round /, "", roundno); sub(/[^0-9].*$/, "", roundno) }
        }
        rl[++rn] = line
      }
      flush()
    }
  '
}

handoff_convert_file() {
  local in="$1" out="$2" report="$3"
  : > "$report"
  _handoff_convert_awk "$report" < "$in" > "$out"
}

handoff_convert_snapshot() {
  local in="$1" out="$2" first
  first="$(awk 'NF { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; exit }' "$in")"
  if [ "$first" = "<session-handoff>" ]; then cp "$in" "$out"; return 2; fi
  [ "$first" = "## Session Handoff" ] || return 1
  awk '
    function tagof(n) { return n == "決策" ? "decisions" : n == "待解問題" ? "open-questions" : n == "失敗嘗試" ? "failed-attempts" : "" }
    function close_field(   e, s, i) {
      if (cur == "") return
      e = n; while (e > 0 && buf[e] !~ /[^ \t]/) e--
      s = 1; while (s <= e && buf[s] !~ /[^ \t]/) s++
      print "<" cur ">"; for (i = s; i <= e; i++) print buf[i]; print "</" cur ">"
      cur = ""; n = 0
    }
    BEGIN { print "<session-handoff>"; want = "decisions open-questions failed-attempts"; split(want, w, " "); wi = 1 }
    /^## Session Handoff[ \t]*$/ { next }
    /^### / {
      name = $0; sub(/^### [ \t]*/, "", name); sub(/[ \t]+$/, "", name)
      close_field(); cur = tagof(name)
      if (cur != w[wi]) { bad = 1; exit }
      wi++; next
    }
    { if (cur == "") { if ($0 ~ /[^ \t]/) { bad = 1; exit } ; next } buf[++n] = $0 }
    END { if (bad || wi != 4) exit 1; close_field(); print "</session-handoff>" }
  ' "$in" > "$out.tmp" || { rm -f "$out.tmp"; return 1; }
  mv "$out.tmp" "$out"
}
