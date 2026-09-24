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

command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }

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

FP="$(sed -n 's/^FINGERPRINT=\([^ ]*\) COUNT=.*/\1/p' <<<"$OUT")"
COUNT="$(sed -n 's/^FINGERPRINT=[^ ]* COUNT=\(.*\)/\1/p' <<<"$OUT")"
ID_MERGED="$(sed -n 's/^ROUND id=\([0-9]*\) file=devlog.feat-merged.md .*/\1/p' <<<"$OUT")"
ID_DELETED="$(sed -n 's/^ROUND id=\([0-9]*\) file=devlog.feat-deleted.md .*/\1/p' <<<"$OUT")"
printf 'old-branches\told branch work\t%s,%s\n' "$ID_MERGED" "$ID_DELETED" > "$TMP/plan.tsv"
APPLY="$(bash "$SCRIPT_DIR/keep-all.sh" --apply "$TMP/plan.tsv" --fingerprint "$FP" --count "$COUNT")"
if [ $? -eq 0 ]; then echo "PASS: apply exits 0"; else echo "FAIL: apply exits 0"; FAIL=1; fi
[ -f "$R/.devlog/devlog.old-branches.md" ] && grep -q "^KEPT=.*devlog.old-branches.md ROUNDS=2" <<<"$APPLY" \
  && echo "PASS: named file written" || { echo "FAIL: named file written"; FAIL=1; }
check "branch files keep their marker and are not deleted" '[ "$(head -n 1 "$R/.devlog/devlog.feat-merged.md")" = "<!-- devlog-origin: branch=feat/merged -->" ]'
check "index written to the current branch file" 'grep -q "devlog.old-branches.md\`：keep-all，2 輪" "$R/.devlog/devlog.feat-live.md"'
check "lock released" '[ ! -e "$R/.devlog/.lock" ] && [ ! -d "$R/.devlog/.lock.d" ]'

bash "$SCRIPT_DIR/keep-all.sh" --apply "$TMP/plan.tsv" --fingerprint "$FP" --count "$COUNT" >/dev/null 2>"$TMP/err"
if [ $? -eq 1 ] && grep -q fingerprint "$TMP/err"; then echo "PASS: stale fingerprint rejected"
else echo "FAIL: stale fingerprint rejected"; FAIL=1; fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
