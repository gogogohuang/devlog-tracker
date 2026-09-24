#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$SCRIPT_DIR/devlog-path.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

git_setup() {
  git -C "$1" init -q
  git -C "$1" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
}

# --- non-git directory: falls back to devlog.md -------------------------
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT"
devlog_resolve_paths "$NONGIT"
[ "$DEVLOG_FILE" = "$NONGIT/.devlog/devlog.md" ] \
  && echo "PASS: non-git falls back to devlog.md" \
  || { echo "FAIL: non-git got $DEVLOG_FILE"; FAIL=1; }

# --- main branch: devlog.md ----------------------------------------------
MAINREPO="$TMP/mainrepo"
mkdir -p "$MAINREPO"
git_setup "$MAINREPO"
git -C "$MAINREPO" branch -M main
devlog_resolve_paths "$MAINREPO"
[ "$DEVLOG_FILE" = "$MAINREPO/.devlog/devlog.md" ] \
  && echo "PASS: main branch keeps devlog.md" \
  || { echo "FAIL: main got $DEVLOG_FILE"; FAIL=1; }

# --- master branch: devlog.md --------------------------------------------
MASTERREPO="$TMP/masterrepo"
mkdir -p "$MASTERREPO"
git_setup "$MASTERREPO"
git -C "$MASTERREPO" branch -M master
devlog_resolve_paths "$MASTERREPO"
[ "$DEVLOG_FILE" = "$MASTERREPO/.devlog/devlog.md" ] \
  && echo "PASS: master branch keeps devlog.md" \
  || { echo "FAIL: master got $DEVLOG_FILE"; FAIL=1; }

# --- feature branch: devlog.<branch>.md ----------------------------------
FEATREPO="$TMP/featrepo"
mkdir -p "$FEATREPO"
git_setup "$FEATREPO"
git -C "$FEATREPO" checkout -q -b feature-x
devlog_resolve_paths "$FEATREPO"
[ "$DEVLOG_FILE" = "$FEATREPO/.devlog/devlog.feature-x.md" ] \
  && echo "PASS: feature branch maps to devlog.feature-x.md" \
  || { echo "FAIL: feature-x got $DEVLOG_FILE"; FAIL=1; }

# --- branch with slash: sanitized ----------------------------------------
SLASHREPO="$TMP/slashrepo"
mkdir -p "$SLASHREPO"
git_setup "$SLASHREPO"
git -C "$SLASHREPO" checkout -q -b feature/foo
devlog_resolve_paths "$SLASHREPO"
[ "$DEVLOG_FILE" = "$SLASHREPO/.devlog/devlog.feature-foo.md" ] \
  && echo "PASS: slash in branch name sanitized to -" \
  || { echo "FAIL: feature/foo got $DEVLOG_FILE"; FAIL=1; }

# --- detached HEAD: falls back to worktree dirname -----------------------
DETACHEDREPO="$TMP/detached-repo"
mkdir -p "$DETACHEDREPO"
git_setup "$DETACHEDREPO"
git -C "$DETACHEDREPO" checkout -q --detach
devlog_resolve_paths "$DETACHEDREPO"
[ "$DEVLOG_FILE" = "$DETACHEDREPO/.devlog/devlog.detached-repo.md" ] \
  && echo "PASS: detached HEAD falls back to worktree dirname" \
  || { echo "FAIL: detached got $DEVLOG_FILE"; FAIL=1; }

# Writes a devlog.md with a project header, the given rounds (as
# "<n>:<STATUS>" pairs), a Checkpoint between rounds 1 and 2, and a
# trailing Kept 索引.
write_main_devlog() {
  local file="$1"; shift
  {
    printf '# 專案摘要\n\nheader line\n'
    local pair n st
    for pair in "$@"; do
      n="${pair%%:*}"; st="${pair#*:}"
      printf '\n## Round %s — t\n\n### Summary\nround %s body\n\n### Status\n%s\n' "$n" "$n" "$st"
      [ "$n" = 1 ] && printf '\n## Checkpoint — t\n\ncheckpoint body\n'
    done
    printf '\n## Kept 索引\n\n- devlog.old.md — kept topic\n'
  } > "$file"
}

# New repo on main with .enabled; leaves the caller on main.
mig_repo() {
  mkdir -p "$1/.devlog"
  : > "$1/.devlog/.enabled"
  git_setup "$1"
  git -C "$1" branch -M main
}

# --- main's last round DONE: new branch starts empty, devlog.md untouched --
DONEREPO="$TMP/donerepo"
mig_repo "$DONEREPO"
write_main_devlog "$DONEREPO/.devlog/devlog.md" 1:DONE 2:DONE
cp "$DONEREPO/.devlog/devlog.md" "$TMP/done-before.md"
echo "main handoff" > "$DONEREPO/.devlog/handoff.md"
git -C "$DONEREPO" checkout -q -b feature-done
devlog_resolve_paths "$DONEREPO"
if [ "$DEVLOG_FILE" = "$DONEREPO/.devlog/devlog.feature-done.md" ] \
  && [ ! -f "$DEVLOG_FILE" ] \
  && cmp -s "$DONEREPO/.devlog/devlog.md" "$TMP/done-before.md" \
  && [ -f "$DONEREPO/.devlog/handoff.md" ] \
  && [ ! -f "$DONEREPO/.devlog/handoff.feature-done.md" ]; then
  echo "PASS: main ending DONE leaves devlog.md alone, branch starts empty"
else
  echo "FAIL: DONE-tail migration moved something (file=$DEVLOG_FILE)"
  FAIL=1
fi

# --- unfinished tail: rounds after the last DONE are cut into branch file --
TAILREPO="$TMP/tailrepo"
mig_repo "$TAILREPO"
write_main_devlog "$TAILREPO/.devlog/devlog.md" 1:DONE 2:DONE 3:BLOCKED 4:IN_PROGRESS
echo "main handoff" > "$TAILREPO/.devlog/handoff.md"
git -C "$TAILREPO" checkout -q -b feature-y
devlog_resolve_paths "$TAILREPO"
MAINF="$TAILREPO/.devlog/devlog.md"
if [ "$DEVLOG_FILE" = "$TAILREPO/.devlog/devlog.feature-y.md" ] \
  && [ -f "$DEVLOG_FILE" ] \
  && [ "$(devlog_list_round_starts "$DEVLOG_FILE" | awk '{print $2}' | tr '\n' ' ')" = "3 4 " ] \
  && [ "$(devlog_list_round_starts "$MAINF" | awk '{print $2}' | tr '\n' ' ')" = "1 2 " ] \
  && ! grep -q "round 3 body\|round 4 body" "$MAINF" \
  && grep -q "^# 專案摘要" "$MAINF" && ! grep -q "^# 專案摘要" "$DEVLOG_FILE" \
  && grep -q "^## Checkpoint" "$MAINF" && ! grep -q "^## Checkpoint" "$DEVLOG_FILE" \
  && grep -q "^## Kept 索引" "$MAINF" && ! grep -q "^## Kept 索引" "$DEVLOG_FILE" \
  && [ ! -f "$TAILREPO/.devlog/handoff.md" ] \
  && grep -q "main handoff" "$TAILREPO/.devlog/handoff.feature-y.md"; then
  echo "PASS: unfinished tail (rounds after last DONE) cut into branch file with handoff"
else
  echo "FAIL: tail migration (file=$DEVLOG_FILE)"
  echo "--- devlog.md"; cat "$MAINF"; echo "--- branch"; cat "$DEVLOG_FILE" 2>/dev/null
  FAIL=1
fi

# --- tail migration is idempotent: branch file exists, nothing re-moves ----
echo "## Round 5 written after migration" >> "$TAILREPO/.devlog/devlog.feature-y.md"
cp "$MAINF" "$TMP/tail-main-after.md"
devlog_resolve_paths "$TAILREPO"
if [ "$DEVLOG_FILE" = "$TAILREPO/.devlog/devlog.feature-y.md" ] \
  && grep -q "Round 5 written after migration" "$DEVLOG_FILE" \
  && cmp -s "$MAINF" "$TMP/tail-main-after.md"; then
  echo "PASS: second resolve is a no-op, content preserved"
else
  echo "FAIL: second resolve altered state, got $DEVLOG_FILE"
  FAIL=1
fi

# --- no DONE round at all: every round moves, header/index stay ----------
NODONEREPO="$TMP/nodonerepo"
mig_repo "$NODONEREPO"
write_main_devlog "$NODONEREPO/.devlog/devlog.md" 1:INTERRUPTED 2:IN_PROGRESS
git -C "$NODONEREPO" checkout -q -b feature-n
devlog_resolve_paths "$NODONEREPO"
if [ "$(devlog_list_round_starts "$DEVLOG_FILE" 2>/dev/null | awk '{print $2}' | tr '\n' ' ')" = "1 2 " ] \
  && [ -z "$(devlog_list_round_starts "$NODONEREPO/.devlog/devlog.md")" ] \
  && grep -q "^## Kept 索引" "$NODONEREPO/.devlog/devlog.md" \
  && grep -q "^## Checkpoint" "$NODONEREPO/.devlog/devlog.md"; then
  echo "PASS: with no DONE round, all rounds move and non-round sections stay"
else
  echo "FAIL: no-DONE migration (file=$DEVLOG_FILE)"
  FAIL=1
fi

# --- stale branch (doesn't contain main's tip): nothing moves -------------
STALEREPO="$TMP/stalerepo"
mig_repo "$STALEREPO"
git -C "$STALEREPO" branch old-branch
git -C "$STALEREPO" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m "main moves on"
write_main_devlog "$STALEREPO/.devlog/devlog.md" 1:DONE 2:IN_PROGRESS
cp "$STALEREPO/.devlog/devlog.md" "$TMP/stale-before.md"
echo "main handoff" > "$STALEREPO/.devlog/handoff.md"
git -C "$STALEREPO" checkout -q old-branch
devlog_resolve_paths "$STALEREPO"
if [ "$DEVLOG_FILE" = "$STALEREPO/.devlog/devlog.old-branch.md" ] \
  && [ ! -f "$DEVLOG_FILE" ] \
  && cmp -s "$STALEREPO/.devlog/devlog.md" "$TMP/stale-before.md" \
  && [ -f "$STALEREPO/.devlog/handoff.md" ]; then
  echo "PASS: checking out a branch that lacks main's tip moves nothing"
else
  echo "FAIL: stale branch took main's tail (file=$DEVLOG_FILE)"
  FAIL=1
fi

# --- migration does NOT fire when .devlog/.enabled is absent (Fix 6) -----
NOENABLEDREPO="$TMP/noenabledrepo"
mkdir -p "$NOENABLEDREPO/.devlog"
git_setup "$NOENABLEDREPO"
git -C "$NOENABLEDREPO" checkout -q -b feature-z
echo "## Round 1 existing content" > "$NOENABLEDREPO/.devlog/devlog.md"
devlog_resolve_paths "$NOENABLEDREPO"
if [ "$DEVLOG_FILE" = "$NOENABLEDREPO/.devlog/devlog.feature-z.md" ] \
  && [ ! -f "$DEVLOG_FILE" ] \
  && [ -f "$NOENABLEDREPO/.devlog/devlog.md" ]; then
  echo "PASS: migration does not fire when .enabled is absent, old devlog.md left untouched"
else
  echo "FAIL: no-.enabled migration file=$DEVLOG_FILE resolved_exists=$([ -f "$DEVLOG_FILE" ] && echo y || echo n) old_exists=$([ -f "$NOENABLEDREPO/.devlog/devlog.md" ] && echo y || echo n)"
  FAIL=1
fi

# --- origin marker: DEVLOG_ORIGIN reflects the raw branch / detached dir ----
devlog_resolve_paths "$MAINREPO"
[ -z "$DEVLOG_ORIGIN" ] \
  && echo "PASS: main has no DEVLOG_ORIGIN" \
  || { echo "FAIL: main DEVLOG_ORIGIN=$DEVLOG_ORIGIN"; FAIL=1; }
devlog_resolve_paths "$NONGIT"
[ -z "$DEVLOG_ORIGIN" ] \
  && echo "PASS: non-git has no DEVLOG_ORIGIN" \
  || { echo "FAIL: non-git DEVLOG_ORIGIN=$DEVLOG_ORIGIN"; FAIL=1; }
devlog_resolve_paths "$SLASHREPO"
[ "$DEVLOG_ORIGIN" = "branch=feature/foo" ] \
  && echo "PASS: DEVLOG_ORIGIN keeps the raw (unsanitized) branch name" \
  || { echo "FAIL: slash DEVLOG_ORIGIN=$DEVLOG_ORIGIN"; FAIL=1; }
devlog_resolve_paths "$DETACHEDREPO"
[ "$DEVLOG_ORIGIN" = "detached=detached-repo" ] \
  && echo "PASS: detached DEVLOG_ORIGIN names the worktree dir" \
  || { echo "FAIL: detached DEVLOG_ORIGIN=$DEVLOG_ORIGIN"; FAIL=1; }

# --- origin marker: written as line 1 when the tail migrates -------------
MARKREPO="$TMP/markrepo"
mig_repo "$MARKREPO"
write_main_devlog "$MARKREPO/.devlog/devlog.md" 1:DONE 2:IN_PROGRESS
git -C "$MARKREPO" checkout -q -b feat/mark
devlog_resolve_paths "$MARKREPO"
if [ "$(head -n 1 "$DEVLOG_FILE")" = "<!-- devlog-origin: branch=feat/mark -->" ] \
  && [ "$(devlog_list_round_starts "$DEVLOG_FILE" | awk '{print $2}' | tr '\n' ' ')" = "2 " ] \
  && ! grep -q "devlog-origin" "$MARKREPO/.devlog/devlog.md"; then
  echo "PASS: migrated branch file starts with its origin marker"
else
  echo "FAIL: migrated marker"; cat "$DEVLOG_FILE" 2>/dev/null; FAIL=1
fi

# --- origin marker: first merge into a missing branch file writes it -----
MERGEREPO="$TMP/mergerepo"
mig_repo "$MERGEREPO"
git -C "$MERGEREPO" checkout -q -b feat/merge
devlog_resolve_paths "$MERGEREPO"
printf '## Round 1 — t\n\n### Status\nDONE\n' > "$TMP/rc1.md"
devlog_merge_round_current "$DEVLOG_FILE" "$TMP/rc1.md"
printf '## Round 2 — t\n\n### Status\nDONE\n' > "$TMP/rc2.md"
devlog_merge_round_current "$DEVLOG_FILE" "$TMP/rc2.md"
if [ "$(head -n 1 "$DEVLOG_FILE")" = "<!-- devlog-origin: branch=feat/merge -->" ] \
  && [ "$(grep -c "devlog-origin" "$DEVLOG_FILE")" = 1 ] \
  && [ "$(devlog_list_round_starts "$DEVLOG_FILE" | awk '{print $2}' | tr '\n' ' ')" = "1 2 " ]; then
  echo "PASS: first merge into a new branch file writes the marker once"
else
  echo "FAIL: merge marker"; cat "$DEVLOG_FILE" 2>/dev/null; FAIL=1
fi

# --- origin marker: devlog.md never gets one -----------------------------
MAINMERGE="$TMP/mainmerge"
mig_repo "$MAINMERGE"
devlog_resolve_paths "$MAINMERGE"
printf '## Round 1 — t\n\n### Status\nDONE\n' > "$TMP/rc3.md"
devlog_merge_round_current "$DEVLOG_FILE" "$TMP/rc3.md"
! grep -q "devlog-origin" "$DEVLOG_FILE" \
  && echo "PASS: devlog.md gets no origin marker" \
  || { echo "FAIL: devlog.md got a marker"; FAIL=1; }

# --- HANDOFF_FILE mirrors DEVLOG_FILE naming (no rename migration) --------
devlog_resolve_paths "$NONGIT"
[ "$HANDOFF_FILE" = "$NONGIT/.devlog/handoff.md" ] \
  && echo "PASS: non-git HANDOFF_FILE is handoff.md" \
  || { echo "FAIL: non-git HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$MAINREPO"
[ "$HANDOFF_FILE" = "$MAINREPO/.devlog/handoff.md" ] \
  && echo "PASS: main HANDOFF_FILE is handoff.md" \
  || { echo "FAIL: main HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$FEATREPO"
[ "$HANDOFF_FILE" = "$FEATREPO/.devlog/handoff.feature-x.md" ] \
  && echo "PASS: feature HANDOFF_FILE is handoff.feature-x.md" \
  || { echo "FAIL: feature HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$SLASHREPO"
[ "$HANDOFF_FILE" = "$SLASHREPO/.devlog/handoff.feature-foo.md" ] \
  && echo "PASS: slash branch HANDOFF_FILE sanitized" \
  || { echo "FAIL: slash HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

devlog_resolve_paths "$DETACHEDREPO"
[ "$HANDOFF_FILE" = "$DETACHEDREPO/.devlog/handoff.detached-repo.md" ] \
  && echo "PASS: detached HANDOFF_FILE uses worktree dirname" \
  || { echo "FAIL: detached HANDOFF_FILE=$HANDOFF_FILE"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
