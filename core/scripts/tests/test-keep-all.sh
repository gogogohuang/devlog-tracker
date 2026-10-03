#!/usr/bin/env bash
# End-to-end check of keep-all.sh in a real git repo: branch-state
# reporting, current-file resolution, and a full scan → apply cycle.
# keep-all.js's own rules are covered by core/scripts/keep-all.test.js.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; FAIL=1; fi; }
round() { printf '## Round %s — %s\n\n### Status\n%s\n\n' "$1" "$2" "$3"; }

# The analysis mode is shell-only; exercise it before the Node-dependent checks.
A="$TMP/analysis project"
mkdir -p "$A/.devlog"
A="$(cd "$A" && pwd -P)"
SRC="$TMP/analysis source.md"
DEST="$A/.devlog/keep-all.analysis.md"
printf '# 分析\n\n- first finding\n- exact bytes, no final newline' > "$SRC"
ANALYSIS_OUT="$(DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" 2>"$TMP/analysis.err")"
ANALYSIS_STATUS=$?
check "AC-1: write-analysis exits 0" '[ "$ANALYSIS_STATUS" -eq 0 ]'
check "AC-1: analysis matches source byte for byte" 'cmp -s "$SRC" "$DEST"'
check "AC-2: stdout reports the absolute analysis path" '[ "$ANALYSIS_OUT" = "ANALYSIS=$DEST" ]'

# Seed independently so overwrite/preservation checks do not depend on AC-1.
printf 'old analysis that must be replaced completely\nold tail\n' > "$DEST"
printf 'new analysis\n' > "$SRC"
ANALYSIS_OUT="$(DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" 2>"$TMP/analysis.err")"
ANALYSIS_STATUS=$?
check "AC-3: overwrite exits 0" '[ "$ANALYSIS_STATUS" -eq 0 ]'
check "AC-3: overwrite replaces all old content" 'cmp -s "$SRC" "$DEST"'

# Without .devlog: write-analysis creates it, and source errors still fail loudly.
NODIR="$TMP/no devlog project"
mkdir -p "$NODIR"
NODIR="$(cd "$NODIR" && pwd -P)"
ANALYSIS_OUT="$(DEVLOG_PROJECT_DIR="$NODIR" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" 2>"$TMP/analysis.err")"
ANALYSIS_STATUS=$?
check "AC-1: write-analysis without .devlog exits 0" '[ "$ANALYSIS_STATUS" -eq 0 ]'
check "AC-1: write-analysis without .devlog writes the analysis" 'cmp -s "$SRC" "$NODIR/.devlog/keep-all.analysis.md"'
check "AC-2: write-analysis without .devlog reports the path" '[ "$ANALYSIS_OUT" = "ANALYSIS=$NODIR/.devlog/keep-all.analysis.md" ]'
printf '' > "$TMP/empty.md"
printf '  \n\t\n' > "$TMP/blank.md"
for bad in "$TMP/nonexistent.md" "$TMP/empty.md" "$TMP/blank.md" ""; do
  rm -rf "$NODIR/.devlog"
  DEVLOG_PROJECT_DIR="$NODIR" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$bad" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
  ANALYSIS_STATUS=$?
  check "AC-4/5/6/7: bad source '$bad' without .devlog exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
  check "AC-4/5/6/7: bad source '$bad' without .devlog has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
  check "AC-4/5/6/7: bad source '$bad' without .devlog does not report NOTHING" '! grep -q NOTHING "$TMP/analysis.out"'
done
rm -rf "$NODIR/.devlog"
DEVLOG_PROJECT_DIR="$NODIR" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis >"$TMP/analysis.out" 2>"$TMP/analysis.err"
ANALYSIS_STATUS=$?
check "AC-7: missing argument without .devlog exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ] && [ -s "$TMP/analysis.err" ]'

printf 'existing analysis must survive\n' > "$DEST"
cp "$DEST" "$TMP/analysis-before.md"
DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$TMP/nonexistent.md" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
ANALYSIS_STATUS=$?
check "AC-4: missing source exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
check "AC-4: missing source has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
check "AC-4: missing source preserves existing analysis" 'cmp -s "$TMP/analysis-before.md" "$DEST"'

# AC-5/AC-6: empty or whitespace-only sources are rejected and create nothing.
for kind in empty blank; do
  rm -f "$DEST"
  if [ "$kind" = empty ]; then : > "$SRC"; else printf '  \n\t\n \n' > "$SRC"; fi
  DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
  ANALYSIS_STATUS=$?
  check "AC-5/6: $kind source exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
  check "AC-5/6: $kind source has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
  check "AC-5/6: $kind source creates no analysis" '[ ! -e "$DEST" ]'
  check "AC-5/6: $kind source leaves no temp file" '! ls "$A/.devlog" | grep -q "keep-all.analysis.md.tmp"'
  printf 'existing analysis must survive\n' > "$DEST"
  DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
  ANALYSIS_STATUS=$?
  check "AC-5/6: $kind source exits nonzero with existing analysis" '[ "$ANALYSIS_STATUS" -ne 0 ]'
  check "AC-5/6: $kind source has a diagnostic with existing analysis" '[ -s "$TMP/analysis.err" ]'
  check "AC-5/6: $kind source preserves existing analysis" 'cmp -s "$TMP/analysis-before.md" "$DEST"'
done

# AC-8/9/10: inject silent failures at the filesystem command boundary.
# cp leaves a partial tmp behind before failing, exercising cleanup as well.
no_analysis_tmp() {
  [ -z "$(find "$A/.devlog" -name '*.tmp*' -print)" ]
}
analysis_lock_reacquirable() {
  [ ! -e "$A/.devlog/.lock" ] && [ ! -e "$A/.devlog/.lock.d" ] || return 1
  (
    # shellcheck source=../devlog-lock.sh
    . "$SCRIPT_DIR/devlog-lock.sh"
    DEVLOG_DIR="$A/.devlog"
    devlog_lock_acquire
    trap 'devlog_lock_release' EXIT
    [ "$LOCK_HELD" -eq 1 ]
  )
}
printf 'valid replacement analysis\n' > "$SRC"
DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
ANALYSIS_STATUS=$?
check "AC-9/10: successful write exits 0" '[ "$ANALYSIS_STATUS" -eq 0 ]'
check "AC-9: successful write leaves no tmp" 'no_analysis_tmp'
check "AC-10: successful write releases lock for immediate acquisition" 'analysis_lock_reacquirable'

for utility in cp mv; do
  FAIL_BIN="$TMP/fail-$utility-bin"
  mkdir -p "$FAIL_BIN"
  if [ "$utility" = cp ]; then
    cat > "$FAIL_BIN/cp" <<'FAKE_CP'
#!/usr/bin/env bash
printf 'partial analysis copy\n' > "${@: -1}"
exit 73
FAKE_CP
  else
    cat > "$FAIL_BIN/mv" <<'FAKE_MV'
#!/usr/bin/env bash
exit 74
FAKE_MV
  fi
  chmod +x "$FAIL_BIN/$utility"
  printf 'existing analysis must survive\n' > "$DEST"
  cp "$DEST" "$TMP/analysis-before.md"
  PATH="$FAIL_BIN:$PATH" DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
  ANALYSIS_STATUS=$?
  check "AC-8: $utility failure exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
  check "AC-8: $utility failure has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
  check "AC-8: $utility failure does not report ANALYSIS=" '! grep -q "ANALYSIS=" "$TMP/analysis.out"'
  check "AC-8: $utility failure preserves existing analysis bytes" 'cmp -s "$TMP/analysis-before.md" "$DEST"'
  check "AC-9: $utility failure leaves no tmp" 'no_analysis_tmp'
  check "AC-10: $utility failure releases lock for immediate acquisition" 'analysis_lock_reacquirable'
done

# AC-7: a missing or empty-string <path> is rejected and preserves the analysis.
printf 'existing analysis must survive\n' > "$DEST"
DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis >"$TMP/analysis.out" 2>"$TMP/analysis.err"
ANALYSIS_STATUS=$?
check "AC-7: missing path exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
check "AC-7: missing path has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
check "AC-7: missing path preserves existing analysis" 'cmp -s "$TMP/analysis-before.md" "$DEST"'
DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
ANALYSIS_STATUS=$?
check "AC-7: empty path exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
check "AC-7: empty path has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
check "AC-7: empty path preserves existing analysis" 'cmp -s "$TMP/analysis-before.md" "$DEST"'

# A directory (or a symlink to one) at the destination is rejected, not filled with the tmp.
rm -f "$DEST"
printf 'replacement\n' > "$SRC"
for kind in dir symlink; do
  rm -rf "$DEST" "$TMP/linked-dir"
  if [ "$kind" = dir ]; then mkdir "$DEST"; else mkdir "$TMP/linked-dir"; ln -s "$TMP/linked-dir" "$DEST"; fi
  DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
  ANALYSIS_STATUS=$?
  check "$kind destination exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
  check "$kind destination has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
  check "$kind destination does not report ANALYSIS=" '! grep -q "ANALYSIS=" "$TMP/analysis.out"'
  check "$kind destination leaves no tmp" 'no_analysis_tmp && [ -z "$(find "$TMP/linked-dir" -type f 2>/dev/null)" ]'
  check "$kind destination releases lock" '[ ! -e "$A/.devlog/.lock" ] && [ ! -d "$A/.devlog/.lock.d" ]'
done
rm -rf "$DEST" "$TMP/linked-dir"

# AC-22: a live process holding the devlog lock makes --write-analysis refuse
# after the contention timeout, leaving that process's lock untouched.
sleep 30 &
HOLDER_PID=$!
mkdir "$A/.devlog/.lock"
printf '%s\n' "$HOLDER_PID" > "$A/.devlog/.lock/pid"
printf 'existing analysis must survive contention\n' > "$DEST"
cp "$DEST" "$TMP/analysis-before.md"
printf 'contended replacement\n' > "$SRC"
DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
ANALYSIS_STATUS=$?
check "AC-22: contended lock exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
check "AC-22: contended lock has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
check "AC-22: contended lock does not report ANALYSIS=" '! grep -q "ANALYSIS=" "$TMP/analysis.out"'
check "AC-22: contended lock preserves existing analysis bytes" 'cmp -s "$TMP/analysis-before.md" "$DEST"'
check "AC-22: contended lock leaves no tmp" 'no_analysis_tmp'
check "AC-22: contended lock keeps the holder's lock and pid" '[ -d "$A/.devlog/.lock" ] && [ "$(cat "$A/.devlog/.lock/pid" 2>/dev/null)" = "$HOLDER_PID" ]'
kill "$HOLDER_PID" 2>/dev/null
wait "$HOLDER_PID" 2>/dev/null
rm -rf "$A/.devlog/.lock"

# A lock without a valid pid (missing, blank or non-numeric) cannot be reclaimed
# as stale, so after the timeout --write-analysis must refuse rather than write.
for pid_kind in missing blank non-numeric; do
  mkdir "$A/.devlog/.lock"
  case "$pid_kind" in
    blank) printf '  \n' > "$A/.devlog/.lock/pid" ;;
    non-numeric) printf 'abc\n' > "$A/.devlog/.lock/pid" ;;
  esac
  printf 'existing analysis must survive pidless lock\n' > "$DEST"
  cp "$DEST" "$TMP/analysis-before.md"
  printf 'pidless replacement\n' > "$SRC"
  DEVLOG_PROJECT_DIR="$A" bash "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" >"$TMP/analysis.out" 2>"$TMP/analysis.err"
  ANALYSIS_STATUS=$?
  check "$pid_kind-pid lock exits nonzero" '[ "$ANALYSIS_STATUS" -ne 0 ]'
  check "$pid_kind-pid lock has a stderr diagnostic" '[ -s "$TMP/analysis.err" ]'
  check "$pid_kind-pid lock does not report ANALYSIS=" '! grep -q "ANALYSIS=" "$TMP/analysis.out"'
  check "$pid_kind-pid lock preserves existing analysis bytes" 'cmp -s "$TMP/analysis-before.md" "$DEST"'
  check "$pid_kind-pid lock leaves no tmp" 'no_analysis_tmp'
  check "$pid_kind-pid lock leaves the lock in place" '[ -d "$A/.devlog/.lock" ]'
  rm -rf "$A/.devlog/.lock"
done

# Keep normal shell utilities available while excluding Node deterministically.
NO_NODE_REPO="$TMP/no-node project"
mkdir -p "$NO_NODE_REPO/.devlog"
git -C "$NO_NODE_REPO" init -q
git -C "$NO_NODE_REPO" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
NO_NODE_REPO="$(cd "$NO_NODE_REPO" && pwd -P)"
NO_NODE_SRC="$TMP/no-node source.md"
# shellcheck disable=SC2034 # read by check() via eval below
NO_NODE_DEST="$NO_NODE_REPO/.devlog/keep-all.analysis.md"
NO_NODE_PATH="$TMP/no-node-bin"
mkdir -p "$NO_NODE_PATH"
for utility in bash cat cp mv mkdir rmdir rm date sleep mktemp git sed awk cut dirname basename tr grep head cksum; do
  UTILITY_PATH="$(command -v "$utility")"
  ln -s "$UTILITY_PATH" "$NO_NODE_PATH/$utility"
done
BASH_BIN="$(command -v bash)"
check "AC-21: fixture excludes Node" '! PATH="$NO_NODE_PATH" "$BASH_BIN" -c "command -v node"'
check "AC-21: fixture is a git repo" 'git -C "$NO_NODE_REPO" rev-parse --is-inside-work-tree >/dev/null'
printf '# 無 Node 分析\n\nexact bytes, no final newline' > "$NO_NODE_SRC"
# shellcheck disable=SC2034 # read by check() via eval below
ANALYSIS_OUT="$(PATH="$NO_NODE_PATH" DEVLOG_PROJECT_DIR="$NO_NODE_REPO" "$BASH_BIN" "$SCRIPT_DIR/keep-all.sh" --write-analysis "$NO_NODE_SRC" 2>"$TMP/no-node.err")"
# shellcheck disable=SC2034 # read by check() via eval below
ANALYSIS_STATUS=$?
check "AC-21: write-analysis without Node exits 0" '[ "$ANALYSIS_STATUS" -eq 0 ]'
check "AC-21: write-analysis without Node copies exact content" 'cmp -s "$NO_NODE_SRC" "$NO_NODE_DEST"'
check "AC-21: write-analysis without Node reports absolute path" '[ "$ANALYSIS_OUT" = "ANALYSIS=$NO_NODE_DEST" ] && [[ "$NO_NODE_DEST" = /* ]]'
check "AC-21: write-analysis without Node does not report NO_NODE" '[[ "$ANALYSIS_OUT" != *NO_NODE* ]] && ! grep -q NO_NODE "$TMP/no-node.err"'

# npm test uses this focused entry point; the hook suite also runs the rest.
if [ "${1:-}" = --write-analysis-tests-only ]; then
  exit "$FAIL"
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: Node-dependent checks"; exit "$FAIL"; }

R="$TMP/repo"
mkdir -p "$R/.devlog"
git -C "$R" init -q
git -C "$R" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
git -C "$R" branch -M main
git -C "$R" branch feat/merged
git -C "$R" checkout -q -b feat/live
git -C "$R" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m live
export DEVLOG_PROJECT_DIR="$R"

{ printf '# proj\n\n'; round 1 2026-09-01T10:00:00+0800 DONE; } > "$R/.devlog/devlog.md"
{ printf '<!-- devlog-origin: branch=feat/live -->\n\n'; round 1 2026-09-02T10:00:00+0800 DONE; round 2 2026-09-02T11:00:00+0800 IN_PROGRESS; } > "$R/.devlog/devlog.feat-live.md"
{ printf '<!-- devlog-origin: branch=feat/merged -->\n\n'; round 1 2026-09-03T10:00:00+0800 DONE; } > "$R/.devlog/devlog.feat-merged.md"
{ printf '<!-- devlog-origin: branch=feat/deleted -->\n\n'; round 1 2026-09-04T10:00:00+0800 DONE; } > "$R/.devlog/devlog.feat-deleted.md"
printf '{"round": 2, "opened_at": "now"}\n' > "$R/.devlog/.round-open"

OUT="$(bash "$SCRIPT_DIR/keep-all.sh" --scan)"
check "current file is the checked-out branch's" 'grep -q "^SOURCE file=devlog.feat-live.md kind=current origin=feat/live origin_from=marker state=active" <<<"$OUT"'
check "devlog.md off main is a branch source" 'grep -q "^SOURCE file=devlog.md kind=branch origin=main" <<<"$OUT"'
check "merged branch reported" 'grep -q "file=devlog.feat-merged.md kind=branch origin=feat/merged origin_from=marker state=merged" <<<"$OUT"'
check "deleted branch reported" 'grep -q "file=devlog.feat-deleted.md kind=branch origin=feat/deleted origin_from=marker state=gone" <<<"$OUT"'
check "open round not movable" 'grep -q "file=devlog.feat-live.md round=2 .* movable=0" <<<"$OUT"'

# AC-11 (characterization): the analysis file is never a SOURCE or ROUND.
printf '## Round 1 — 2026-09-05T10:00:00+0800\n\n### Status\nDONE\n\nanalysis notes\n' > "$R/.devlog/keep-all.analysis.md"
# shellcheck disable=SC2034 # read by check() via eval below
WITH_ANALYSIS="$(bash "$SCRIPT_DIR/keep-all.sh" --scan)"
rm -f "$R/.devlog/keep-all.analysis.md"
check "AC-11: scan output identical with analysis file present" '[ "$WITH_ANALYSIS" = "$OUT" ]'
check "AC-11: scan never mentions the analysis file" '! grep -q "keep-all.analysis" <<<"$WITH_ANALYSIS"'

FP="$(sed -n 's/^FINGERPRINT=\([^ ]*\) COUNT=.*/\1/p' <<<"$OUT")"
COUNT="$(sed -n 's/^FINGERPRINT=[^ ]* COUNT=\(.*\)/\1/p' <<<"$OUT")"
ID_MERGED="$(sed -n 's/^ROUND id=\([0-9]*\) file=devlog.feat-merged.md .*/\1/p' <<<"$OUT")"
ID_DELETED="$(sed -n 's/^ROUND id=\([0-9]*\) file=devlog.feat-deleted.md .*/\1/p' <<<"$OUT")"
printf 'old-branches\told branch work\t%s,%s\n' "$ID_MERGED" "$ID_DELETED" > "$TMP/plan.tsv"
# AC-12: run a real apply against an independent copy with analysis present.
P="$TMP/apply with analysis"
cp -R "$R" "$P"
printf '## Round 99 — 2026-09-06T10:00:00+0800\n\n### Status\nDONE\n\nanalysis bytes, no final newline' > "$P/.devlog/keep-all.analysis.md"
cp "$P/.devlog/keep-all.analysis.md" "$TMP/apply-analysis-before.md"
P_SCAN="$(DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/keep-all.sh" --scan)"
P_FP="$(sed -n 's/^FINGERPRINT=\([^ ]*\) COUNT=.*/\1/p' <<<"$P_SCAN")"
P_COUNT="$(sed -n 's/^FINGERPRINT=[^ ]* COUNT=\(.*\)/\1/p' <<<"$P_SCAN")"
DEVLOG_PROJECT_DIR="$P" bash "$SCRIPT_DIR/keep-all.sh" --apply "$TMP/plan.tsv" --fingerprint "$P_FP" --count "$P_COUNT" >"$TMP/apply-analysis.out" 2>"$TMP/apply-analysis.err"
# shellcheck disable=SC2034 # read by check() via eval below
P_STATUS=$?
check "AC-12: apply with existing analysis exits 0" '[ "$P_STATUS" -eq 0 ]'
check "AC-12: apply does not modify or delete existing analysis" 'cmp -s "$TMP/apply-analysis-before.md" "$P/.devlog/keep-all.analysis.md"'

APPLY="$(bash "$SCRIPT_DIR/keep-all.sh" --apply "$TMP/plan.tsv" --fingerprint "$FP" --count "$COUNT")"
if [ $? -eq 0 ]; then echo "PASS: apply exits 0"; else echo "FAIL: apply exits 0"; FAIL=1; fi
[ -f "$R/.devlog/devlog.old-branches.md" ] && grep -q "^KEPT=.*devlog.old-branches.md ROUNDS=2" <<<"$APPLY" \
  && echo "PASS: named file written" || { echo "FAIL: named file written"; FAIL=1; }
check "emptied merged/gone branch files deleted" '[ ! -e "$R/.devlog/devlog.feat-merged.md" ] && [ ! -e "$R/.devlog/devlog.feat-deleted.md" ] && grep -q "^DELETED=.*devlog.feat-merged.md" <<<"$APPLY"'
check "index written to the current branch file" 'grep -q "devlog.old-branches.md\`：keep-all，2 輪" "$R/.devlog/devlog.feat-live.md"'
check "AC-12: apply does not create absent analysis" '[ ! -e "$R/.devlog/keep-all.analysis.md" ]'
check "lock released" '[ ! -e "$R/.devlog/.lock" ] && [ ! -d "$R/.devlog/.lock.d" ]'

bash "$SCRIPT_DIR/keep-all.sh" --apply "$TMP/plan.tsv" --fingerprint "$FP" --count "$COUNT" >/dev/null 2>"$TMP/err"
if [ $? -eq 1 ] && grep -q fingerprint "$TMP/err"; then echo "PASS: stale fingerprint rejected"
else echo "FAIL: stale fingerprint rejected"; FAIL=1; fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
