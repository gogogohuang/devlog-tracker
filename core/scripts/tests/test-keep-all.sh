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

# Keep normal shell utilities available while excluding Node deterministically.
NO_NODE_PATH="$TMP/no-node-bin"
mkdir -p "$NO_NODE_PATH"
for utility in bash cat cp mv mkdir rmdir rm date sleep mktemp git sed awk cut dirname basename tr grep head cksum; do
  UTILITY_PATH="$(command -v "$utility")"
  ln -s "$UTILITY_PATH" "$NO_NODE_PATH/$utility"
done
BASH_BIN="$(command -v bash)"
check "no-node fixture excludes Node" '! PATH="$NO_NODE_PATH" "$BASH_BIN" -c "command -v node"'
rm -f "$DEST"
printf 'analysis without Node\n' > "$SRC"
# shellcheck disable=SC2034 # read by check() via eval below
ANALYSIS_OUT="$(PATH="$NO_NODE_PATH" DEVLOG_PROJECT_DIR="$A" "$BASH_BIN" "$SCRIPT_DIR/keep-all.sh" --write-analysis "$SRC" 2>"$TMP/analysis.err")"
# shellcheck disable=SC2034 # read by check() via eval below
ANALYSIS_STATUS=$?
check "write-analysis without Node exits 0" '[ "$ANALYSIS_STATUS" -eq 0 ]'
check "write-analysis without Node copies exact content" 'cmp -s "$SRC" "$DEST"'
check "write-analysis without Node reports absolute path" '[ "$ANALYSIS_OUT" = "ANALYSIS=$DEST" ]'

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
WITH_ANALYSIS="$(bash "$SCRIPT_DIR/keep-all.sh" --scan)"
rm -f "$R/.devlog/keep-all.analysis.md"
check "AC-11: scan output identical with analysis file present" '[ "$WITH_ANALYSIS" = "$OUT" ]'
check "AC-11: scan never mentions the analysis file" '! grep -q "keep-all.analysis" <<<"$WITH_ANALYSIS"'

FP="$(sed -n 's/^FINGERPRINT=\([^ ]*\) COUNT=.*/\1/p' <<<"$OUT")"
COUNT="$(sed -n 's/^FINGERPRINT=[^ ]* COUNT=\(.*\)/\1/p' <<<"$OUT")"
ID_MERGED="$(sed -n 's/^ROUND id=\([0-9]*\) file=devlog.feat-merged.md .*/\1/p' <<<"$OUT")"
ID_DELETED="$(sed -n 's/^ROUND id=\([0-9]*\) file=devlog.feat-deleted.md .*/\1/p' <<<"$OUT")"
printf 'old-branches\told branch work\t%s,%s\n' "$ID_MERGED" "$ID_DELETED" > "$TMP/plan.tsv"
APPLY="$(bash "$SCRIPT_DIR/keep-all.sh" --apply "$TMP/plan.tsv" --fingerprint "$FP" --count "$COUNT")"
if [ $? -eq 0 ]; then echo "PASS: apply exits 0"; else echo "FAIL: apply exits 0"; FAIL=1; fi
[ -f "$R/.devlog/devlog.old-branches.md" ] && grep -q "^KEPT=.*devlog.old-branches.md ROUNDS=2" <<<"$APPLY" \
  && echo "PASS: named file written" || { echo "FAIL: named file written"; FAIL=1; }
check "emptied merged/gone branch files deleted" '[ ! -e "$R/.devlog/devlog.feat-merged.md" ] && [ ! -e "$R/.devlog/devlog.feat-deleted.md" ] && grep -q "^DELETED=.*devlog.feat-merged.md" <<<"$APPLY"'
check "index written to the current branch file" 'grep -q "devlog.old-branches.md\`：keep-all，2 輪" "$R/.devlog/devlog.feat-live.md"'
check "lock released" '[ ! -e "$R/.devlog/.lock" ] && [ ! -d "$R/.devlog/.lock.d" ]'

bash "$SCRIPT_DIR/keep-all.sh" --apply "$TMP/plan.tsv" --fingerprint "$FP" --count "$COUNT" >/dev/null 2>"$TMP/err"
if [ $? -eq 1 ] && grep -q fingerprint "$TMP/err"; then echo "PASS: stale fingerprint rejected"
else echo "FAIL: stale fingerprint rejected"; FAIL=1; fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
