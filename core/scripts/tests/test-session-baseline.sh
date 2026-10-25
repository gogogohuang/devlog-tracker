#!/usr/bin/env bash
# Session baseline (docs/design/devlog-ignore-session-baseline.md D4–D7):
# library semantics, lifecycle hooks, enforce <files> narrowing, direct
# files-snapshot.sh execution, and fail-open behaviour.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/xml-fixture.sh
. "$SCRIPT_DIR/tests/lib/xml-fixture.sh"
# shellcheck source=../session-baseline.sh
. "$SCRIPT_DIR/session-baseline.sh"
# shellcheck source=../workspace-snapshot.sh
. "$SCRIPT_DIR/workspace-snapshot.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAIL=0
assert_eq() {
  if [ "$3" = "$2" ]; then echo "PASS: $1"
  else echo "FAIL: $1"; printf '  expected: %s\n  actual:   %s\n' "$2" "$3"; FAIL=1; fi
}
exists() { if [ -e "$1" ]; then echo 0; else echo 1; fi; }
assert_has() {
  case "$3" in *"$2"*) echo "PASS: $1" ;; *) echo "FAIL: $1 (missing: $2)"; printf '  in: %s\n' "$3"; FAIL=1 ;; esac
}
assert_lacks() {
  case "$3" in *"$2"*) echo "FAIL: $1 (unexpected: $2)"; printf '  in: %s\n' "$3"; FAIL=1 ;; *) echo "PASS: $1" ;; esac
}

n=0
new_repo() {
  n=$((n + 1))
  R="$TMP_ROOT/r$n"
  mkdir -p "$R/.devlog"
  touch "$R/.devlog/.enabled"
  git -C "$R" init -q -b main
  git -C "$R" config user.email test@example.com
  git -C "$R" config user.name test
  echo '.devlog/' > "$R/.gitignore"
  echo one > "$R/a.txt"; echo one > "$R/b.txt"; echo one > "$R/c.txt"
  git -C "$R" add -A
  git -C "$R" commit -q -m init
  BF="$R/.devlog/.session-baseline"
}

# --- library semantics --------------------------------------------------------
new_repo
echo pre >> "$R/a.txt"            # pre-existing dirty, will stay untouched
echo pre >> "$R/b.txt"            # pre-existing dirty, will be modified again
echo pre > "$R/untracked.txt"
mkdir "$R/dir"; echo 1 > "$R/dir/x"
assert_eq "no baseline: session_changes rc 3" 3 "$(session_changes "$R" >/dev/null 2>&1; echo $?)"
assert_eq "no baseline: prints nothing" "" "$(session_changes "$R" 2>/dev/null)"
session_baseline_write "$R" sess-1; assert_eq "write rc 0" 0 $?
assert_eq "header" "# devlog-session-baseline v1" "$(sed -n 1p "$BF")"
assert_eq "session_id line" "session_id=sess-1" "$(sed -n 2p "$BF")"
assert_has "baseline lists dirty file with hash" "$(git -C "$R" hash-object "$R/a.txt")	a.txt" "$(cat "$BF")"
assert_has "baseline lists untracked dir entry" "	dir/" "$(cat "$BF")"
assert_lacks "baseline excludes .devlog/" ".devlog" "$(tail -n +3 "$BF")"
assert_eq "tmp file cleaned" "" "$(find "$R/.devlog" -name '*tmp*')"
assert_eq "valid" 0 "$(session_baseline_valid "$R"; echo $?)"
assert_eq "nothing changed yet -> empty, rc 0" "0:" "$(session_changes "$R" >"$TMP_ROOT/o" 2>&1; echo "$?:$(cat "$TMP_ROOT/o")")"

echo more >> "$R/b.txt"                       # pre-existing modified in-session
echo new > "$R/new.txt"                        # brand new
rm "$R/c.txt"                                  # deleted in-session
echo 2 > "$R/dir/y"                            # untracked dir content changed
git -C "$R" status --short >/dev/null
OUT="$(session_changes "$R")"
assert_has "new file counted" "新增：" "$OUT"
assert_has "new file listed" "new.txt" "$OUT"
assert_has "untracked dir (changed) counted" "dir/" "$OUT"
assert_has "pre-existing modified in-session counted" "修改：b.txt" "$OUT"
assert_has "deleted counted" "刪除：c.txt" "$OUT"
assert_lacks "pre-existing untouched excluded" "a.txt" "$OUT"
assert_lacks "pre-existing untouched untracked excluded" "untracked.txt" "$OUT"

# ignore applied at read time (patterns added after the baseline was written)
printf 'new.txt\n' > "$R/.devlogignore"
OUT="$(session_changes "$R")"
assert_lacks "ignore applied at read time" "new.txt" "$OUT"
assert_has "ignore keeps others" "b.txt" "$OUT"
rm "$R/.devlogignore"

# --- untracked dir unchanged -> excluded -------------------------------------------
new_repo
mkdir "$R/gen"; echo 1 > "$R/gen/f"
session_baseline_write "$R" s
assert_eq "untracked dir untouched -> no changes" "" "$(session_changes "$R")"

# --- direct execution of files-snapshot.sh ---------------------------------------
new_repo
echo pre >> "$R/a.txt"
assert_eq "direct exec, no baseline: whole dirty listing" "修改：a.txt" "$(bash "$SCRIPT_DIR/files-snapshot.sh" "$R")"
session_baseline_write "$R" s
echo x >> "$R/b.txt"
assert_eq "direct exec, baseline: session changes only" "修改：b.txt" "$(bash "$SCRIPT_DIR/files-snapshot.sh" "$R")"
assert_eq "sourced files_snapshot unchanged (whole listing)" "修改：a.txt, b.txt" "$(files_snapshot "$R")"

# --- fail-open (D7) --------------------------------------------------------------
new_repo
echo pre >> "$R/a.txt"
printf 'garbage\nsession_id=x\n' > "$BF"
assert_eq "bad header -> invalid" 1 "$(session_baseline_valid "$R"; echo $?)"
assert_eq "bad header -> rc 3, no output" "3:" "$(session_changes "$R" >"$TMP_ROOT/o" 2>/dev/null; echo "$?:$(cat "$TMP_ROOT/o")")"
assert_eq "bad header: direct exec falls back" "修改：a.txt" "$(bash "$SCRIPT_DIR/files-snapshot.sh" "$R")"
: > "$BF"
assert_eq "empty file -> invalid" 1 "$(session_baseline_valid "$R"; echo $?)"
chmod 000 "$BF"
if [ -r "$BF" ]; then echo "SKIP: unreadable baseline (running as root)"
else assert_eq "unreadable -> invalid" 1 "$(session_baseline_valid "$R"; echo $?)"; fi
chmod 644 "$BF"; rm -f "$BF"
NG="$TMP_ROOT/nongit"; mkdir -p "$NG/.devlog"
session_baseline_write "$NG" s; _rc=$?
assert_eq "non-git: write rc 1, no file" "1:" "$_rc:$(find "$NG/.devlog" -name '*baseline*')"
session_changes "$NG" >/dev/null 2>&1; assert_eq "non-git: session_changes non-zero" 3 $?
# hash failure: unreadable dirty file
echo secret > "$R/locked.txt"; chmod 000 "$R/locked.txt"
if [ -r "$R/locked.txt" ]; then echo "SKIP: hash failure (running as root)"
else
  session_baseline_write "$R" s; assert_eq "hash failure: write rc 1" 1 $?
  assert_eq "hash failure: no baseline file" 1 "$(session_baseline_valid "$R"; echo $?)"
fi
chmod 644 "$R/locked.txt"; rm -f "$R/locked.txt"

# --- lifecycle: SessionStart --------------------------------------------------
ss() { # ss DIR SOURCE [SESSION_ID] [PLATFORM]
  local json
  if [ -n "${3:-}" ]; then json="{\"source\":\"$2\",\"session_id\":\"$3\"}"; else json="{\"source\":\"$2\"}"; fi
  printf '%s' "$json" | DEVLOG_PROJECT_DIR="$1" DEVLOG_PLATFORM="${4:-}" bash "$SCRIPT_DIR/session-start-devlog.sh" >/dev/null 2>&1
}
new_repo
echo pre >> "$R/a.txt"
ss "$R" startup s1; assert_eq "startup creates" "session_id=s1" "$(sed -n 2p "$BF")"
echo post >> "$R/b.txt"
ss "$R" resume s1
assert_lacks "resume keeps existing baseline (b.txt not absorbed)" "b.txt" "$(cat "$BF")"
ss "$R" compact s1
assert_lacks "compact keeps existing baseline" "b.txt" "$(cat "$BF")"
ss "$R" fork s2
assert_eq "fork updates session_id" "session_id=s2" "$(sed -n 2p "$BF")"
assert_lacks "fork keeps content" "b.txt" "$(cat "$BF")"
ss "$R" clear s3
assert_eq "clear rebuilds (new id)" "session_id=s3" "$(sed -n 2p "$BF")"
assert_has "clear rebuilds (absorbs b.txt)" "	b.txt" "$(cat "$BF")"
echo more >> "$R/c.txt"
ss "$R" startup s4
assert_has "startup rebuilds" "	c.txt" "$(cat "$BF")"
rm -f "$BF"; ss "$R" resume s5
assert_eq "resume creates when missing" "session_id=s5" "$(sed -n 2p "$BF")"
rm -f "$BF"; ss "$R" compact
assert_eq "compact creates when missing (no id)" "session_id=" "$(sed -n 2p "$BF")"
rm -f "$BF"; ss "$R" fork f1
assert_eq "fork creates when missing" "session_id=f1" "$(sed -n 2p "$BF")"
# gated on .enabled
new_repo; rm "$R/.devlog/.enabled"; ss "$R" startup s
assert_eq "not enabled -> no baseline" 1 "$(exists "$BF")"
# context=off: SessionStart touches no .devlog state
new_repo; printf 'off' > "$R/.devlog-session-context"; ss "$R" startup s
assert_eq "context=off: SessionStart writes no baseline" 1 "$(exists "$BF")"
# Codex / Cursor use @platform file; claude file untouched
new_repo
ss "$R" startup "" codex
assert_eq "codex baseline file" 0 "$(exists "$R/.devlog/.session-baseline@codex")"
assert_eq "codex does not touch claude file" 1 "$(exists "$BF")"
ss "$R" startup "" cursor
assert_eq "cursor baseline file" 0 "$(exists "$R/.devlog/.session-baseline@cursor")"
# Codex wrapper reaches the same path (payload is {source} only)
new_repo
printf '{"source":"startup","cwd":"%s"}' "$R" | bash "$SCRIPT_DIR/../../codex/hooks/on-session-start.sh" >/dev/null 2>&1
assert_eq "codex wrapper reaches baseline" 0 "$(exists "$R/.devlog/.session-baseline@codex")"

# --- lifecycle: round-start ---------------------------------------------------
rs() { printf '{"prompt":"hi","session_id":"%s"}' "$2" | CLAUDE_PROJECT_DIR="$1" DEVLOG_PROJECT_DIR="$1" bash "$SCRIPT_DIR/round-start.sh" >/dev/null 2>&1; }
new_repo
echo pre >> "$R/a.txt"
rs "$R" r1; assert_eq "round-start lazy create" "session_id=r1" "$(sed -n 2p "$BF")"
echo post >> "$R/b.txt"
rs "$R" r1; assert_lacks "same id keeps baseline" "b.txt" "$(cat "$BF")"
rs "$R" r2; assert_eq "differing id rebuilds" "session_id=r2" "$(sed -n 2p "$BF")"
assert_has "rebuild absorbs current dirt" "	b.txt" "$(cat "$BF")"
ss "$R" startup ""   # empty id
echo later >> "$R/c.txt"
rs "$R" r3; assert_eq "empty id adopted" "session_id=r3" "$(sed -n 2p "$BF")"
assert_lacks "adopting id keeps content" "c.txt" "$(cat "$BF")"
printf '{"prompt":"<command-name>/devlog-tracker:ignore</command-name>","session_id":"zz"}' \
  | CLAUDE_PROJECT_DIR="$R" bash "$SCRIPT_DIR/round-start.sh" >/dev/null 2>&1
assert_eq "ignore command: no Round opened" 1 "$(exists "$R/.devlog/.round-open")"
assert_eq "ignore command: baseline untouched" "session_id=r3" "$(sed -n 2p "$BF")"
assert_eq "ignore command: no new Round skeleton" 1 "$(exists "$R/.devlog/.round-current.md")"

# --- context=off: round-start lazy path is the only mechanism
new_repo
printf off > "$R/.devlog-session-context"
ss "$R" startup s0
assert_eq "context off: SessionStart writes no baseline" 1 "$(exists "$BF")"
rs "$R" o1; assert_eq "context off: round-start lazy create" "session_id=o1" "$(sed -n 2p "$BF")"
echo moved >> "$R/b.txt"
rs "$R" o2; assert_eq "context off: differing id (fork) rebuilds" "session_id=o2" "$(sed -n 2p "$BF")"
assert_has "context off: rebuild absorbs current dirt" "	b.txt" "$(cat "$BF")"
ss "$R" startup s9
assert_eq "context off: SessionStart leaves baseline alone" "session_id=o2" "$(sed -n 2p "$BF")"

# --- failed required rebuild removes the stale baseline
SHIM="$(mktemp -d "$TMP_ROOT/shim.XXXXXX")"
REAL_GIT="$(command -v git)"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = hash-object ] && exit 1; done\nexec "%s" "$@"\n' "$REAL_GIT" > "$SHIM/git"
chmod +x "$SHIM/git"
new_repo
echo d >> "$R/a.txt"
session_baseline_write "$R" old
assert_eq "stale: old baseline present" 0 "$(exists "$BF")"
( PATH="$SHIM:$PATH"; session_baseline_on_session_start "$R" startup new )
assert_eq "stale: startup rebuild failure leaves no baseline" 1 "$(exists "$BF")"
assert_eq "stale: session_changes rc 3" 3 "$(session_changes "$R" >/dev/null 2>&1; echo $?)"
session_baseline_write "$R" old
( PATH="$SHIM:$PATH"; session_baseline_ensure "$R" other )
assert_eq "stale: ensure rebuild failure leaves no baseline" 1 "$(exists "$BF")"

# --- directory fingerprint keeps path<->content identity; symlinks hash link text
new_repo
mkdir "$R/nd"; echo A > "$R/nd/a"; echo B > "$R/nd/b"
session_baseline_write "$R" s
echo B > "$R/nd/a"; echo A > "$R/nd/b"
assert_has "swapping child contents counts as change" "nd/" "$(session_changes "$R" 2>/dev/null)"
session_baseline_write "$R" s
mv "$R/nd/a" "$R/nd/a2"
assert_has "renaming a child counts as change" "nd/" "$(session_changes "$R" 2>/dev/null)"
new_repo
echo same > "$R/t1"; echo same > "$R/t2"; mkdir "$R/ld"; echo x > "$R/ld/f"
ln -s t1 "$R/lnk"; ln -s ld "$R/dlnk"
session_baseline_write "$R" s
assert_has "symlink to dir is not DIR" "$(printf 'ld' | git -C "$R" hash-object --stdin)	dlnk" "$(cat "$BF")"
assert_lacks "no DIR entry for dir symlink" "DIR	dlnk" "$(cat "$BF")"
rm "$R/lnk"; ln -s t2 "$R/lnk"
assert_has "retargeting symlink (same content) counts" "lnk" "$(session_changes "$R" 2>/dev/null)"
assert_lacks "unchanged dir symlink not reported" "dlnk" "$(session_changes "$R" 2>/dev/null)"

# --- pause removes baseline ---------------------------------------------------
new_repo
ss "$R" startup s; ss "$R" startup "" codex
OUT="$(DEVLOG_PROJECT_DIR="$R" bash "$SCRIPT_DIR/pause-devlog.sh")"
assert_eq "pause output" "PAUSED" "$OUT"
assert_eq "pause removes baselines" "" "$(find "$R/.devlog" -name '*session-baseline*')"
# SessionEnd does not delete
new_repo; ss "$R" startup s
printf '{}' | DEVLOG_PROJECT_DIR="$R" CLAUDE_PROJECT_DIR="$R" bash "$SCRIPT_DIR/on-session-end.sh" >/dev/null 2>&1
assert_eq "SessionEnd keeps baseline" 0 "$(exists "$BF")"

# --- enforce <files> 尚未 commit (fails-before / passes-after) ----------------
new_repo
D="$R/.devlog"
write_round() { # $1 = files body
  {
    echo "## Round 1 — 2026-09-10T00:00:00+08:00"; echo
    echo "### Summary"; echo "fixture"; echo
    echo "### Reply"; echo "fixture reply."; echo
    echo "### Handoff"
    echo "#### 檔案"; printf '%s\n' "$1"
    echo "#### 工作區"; workspace_snapshot "$R"
    echo "#### 現況"; echo "fixture"
    echo "#### 完成條件"; echo "observable done via test."
    echo "#### 下一步"; echo "edit hooks/scripts/enforce-devlog.sh"; echo
    echo "### Session Handoff"; echo
    echo "#### 決策"; echo "- （無）"; echo
    echo "#### 待解問題"; echo "- fixture open"; echo
    echo "#### 失敗嘗試"; echo "- （無）"; echo
    echo "### Status"; echo "IN_PROGRESS"
  } > "$D/.round-current.md"
  xml_fixture "$D/.round-current.md"
}
run_enforce() {
  ERR="$(printf '{}' | CLAUDE_PROJECT_DIR="$R" bash "$SCRIPT_DIR/enforce-devlog.sh" 2>&1 >/dev/null)"; RC=$?
}
echo pre >> "$R/a.txt"                 # dirty BEFORE the session
rs "$R" e1                             # round-start creates the baseline (and opens a Round)
echo mine >> "$R/b.txt"                # this session's change
write_round "尚未 commit：
修改：a.txt"
run_enforce
assert_eq "claim of pre-existing untouched file BLOCKED (was: accepted)" 2 "$RC"
assert_has "specific pre-existing message" "在本 session 開始前就已存在且未變動" "$ERR"
assert_has "hint list shows session change" "修改：b.txt" "$ERR"
assert_lacks "hint list omits pre-existing file" "修改：a.txt" "$(printf '%s' "$ERR" | sed -n '/實際/,$p')"
rs "$R" e1
write_round "尚未 commit：
修改：b.txt"
run_enforce
assert_eq "claim of session change accepted" 0 "$RC"
rs "$R" e1
write_round "尚未 commit：
修改：nonexistent.txt"
run_enforce
assert_eq "claim of clean/unknown path still blocked" 2 "$RC"
assert_lacks "unknown path uses the generic message" "已存在且未變動" "$ERR"
# no baseline -> exactly today's behaviour (pre-existing dirty accepted)
rm -f "$BF"
rs "$R" "" ; rm -f "$BF"
write_round "尚未 commit：
修改：a.txt"
run_enforce
assert_eq "no valid baseline: pre-existing dirty claim accepted (today's behaviour)" 0 "$RC"
# corrupt baseline -> same fallback, hook not broken
rs "$R" ""; printf 'junk\n' > "$BF"
write_round "尚未 commit：
修改：a.txt"
run_enforce
assert_eq "corrupt baseline: falls back, exit 0" 0 "$RC"

[ "$FAIL" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
