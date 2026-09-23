#!/usr/bin/env bash
# Self-check for promote-{sources,target,write}.sh
# (docs/design/read-side-and-promote.md D).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAIL=0
assert_line() {
  local desc="$1" expected="$2" out="$3"
  if printf '%s\n' "$out" | grep -qxF "$expected"; then echo "PASS: $desc"
  else echo "FAIL: $desc (missing [$expected] in: $out)"; FAIL=1; fi
}
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $desc"
  else echo "FAIL: $desc (expected [$expected] got [$actual])"; FAIL=1; fi
}
new_project() { local d; d="$(mktemp -d "$TMP_ROOT/p.XXXXXX")"; (cd "$d" && pwd); }

# === promote-sources.sh =========================================================
P="$(new_project)"
assert_eq "sources: no devlog -> NO_SOURCES" "NO_SOURCES" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-sources.sh")"

mkdir -p "$P/.devlog"
cat > "$P/.devlog/devlog.md" <<'EOF'
## Round 1 — 2026-09-01T10:00:00+0800

### Summary
x

### Status
DONE
EOF
assert_eq "sources: devlog without index/checkpoint -> NO_SOURCES" "NO_SOURCES" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-sources.sh")"

cat >> "$P/.devlog/devlog.md" <<'EOF'

```
## Checkpoint fake inside fence
```

## Checkpoint（Round 1-1）
### 決策
- always run shellcheck

## Kept 索引
- `devlog.topic-a.md`：Round 1-1，kept_at 2026-09-05T00:00:00+0800，topic a
- `devlog.ghost.md`：Round 2-2，kept_at 2026-09-05T00:00:00+0800，gone

## Lessons 索引
- `devlog.lessons.lock-files.md`：1 則，最新一則「x。」（updated_at 2026-09-01T00:00:00+0800）
EOF
printf 'kept\n' > "$P/.devlog/devlog.topic-a.md"
printf '# Lessons: lock-files\n' > "$P/.devlog/devlog.lessons.lock-files.md"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-sources.sh")"
assert_line "sources: kept file exists" "FILE=$P/.devlog/devlog.topic-a.md KIND=kept EXISTS=1" "$OUT"
assert_line "sources: kept ghost row" "FILE=$P/.devlog/devlog.ghost.md KIND=kept EXISTS=0" "$OUT"
assert_line "sources: lessons file" "FILE=$P/.devlog/devlog.lessons.lock-files.md KIND=lessons EXISTS=1" "$OUT"
CP_LINE="$(grep -n '^## Checkpoint（Round 1-1）' "$P/.devlog/devlog.md" | cut -d: -f1)"
assert_line "sources: real checkpoint line" "CHECKPOINT=$P/.devlog/devlog.md:$CP_LINE" "$OUT"
assert_eq "sources: fenced checkpoint ignored" "1" "$(printf '%s\n' "$OUT" | grep -c '^CHECKPOINT=')"

# === promote-target.sh ==========================================================
P="$(new_project)"
assert_eq "target: empty project -> CLAUDE.md" "TARGET=$P/CLAUDE.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

printf '@AGENTS.md\n\n' > "$P/CLAUDE.md"
assert_eq "target: CLAUDE.md only imports AGENTS.md -> AGENTS.md" "TARGET=$P/AGENTS.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

printf '# Rules\n\n@AGENTS.md\n' > "$P/CLAUDE.md"
assert_eq "target: CLAUDE.md with own content -> CLAUDE.md" "TARGET=$P/CLAUDE.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

P="$(new_project)"
mkdir -p "$P/.codex"; printf '{}\n' > "$P/.codex/hooks.json"
assert_eq "target: codex-only (hooks.json) -> AGENTS.md" "TARGET=$P/AGENTS.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

P="$(new_project)"
mkdir -p "$P/.agents/skills/devlog-start"
assert_eq "target: codex-only (skills) -> AGENTS.md" "TARGET=$P/AGENTS.md" "$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"

P="$(new_project)"
printf '# Mine\n\n<!-- devlog-tracker:rules:begin -->\n## devlog-tracker 沉澱的規範\n\n- a\n- b\n<!-- devlog-tracker:rules:end -->\n' > "$P/CLAUDE.md"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-target.sh")"
assert_line "target: existing block counted" "EXISTING=2" "$OUT"

# === promote-write.sh ==========================================================
BEGIN_MARK='<!-- devlog-tracker:rules:begin -->'
END_MARK='<!-- devlog-tracker:rules:end -->'
P="$(new_project)"
RULES="$TMP_ROOT/rules.txt"

# --- target missing -> created with header ---------------------------------------
printf '  改核心腳本後跑 run-tests.sh  \n\n- 一般 PR 不改版號\n' > "$RULES"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES")"
assert_eq "write: new file result" "ADDED=2 SKIPPED_DUP=0 TARGET=$P/CLAUDE.md" "$OUT"
EXPECTED="$(printf '%s\n## devlog-tracker 沉澱的規範\n\n- 改核心腳本後跑 run-tests.sh\n- 一般 PR 不改版號\n%s' "$BEGIN_MARK" "$END_MARK")"
assert_eq "write: new file content (trimmed, '- ' prefixed, blank skipped)" "$EXPECTED" "$(cat "$P/CLAUDE.md")"

# --- existing content without block -> appended after a blank line -------------------
P="$(new_project)"
printf '# Mine\nkeep me' > "$P/CLAUDE.md"
printf 'rule one\n' > "$RULES"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
EXPECTED="$(printf '# Mine\nkeep me\n\n%s\n## devlog-tracker 沉澱的規範\n\n- rule one\n%s' "$BEGIN_MARK" "$END_MARK")"
assert_eq "write: appended after existing content (missing trailing newline handled)" "$EXPECTED" "$(cat "$P/CLAUDE.md")"

# --- existing block -> inserted before end mark; content after block kept -----------
printf '\n## After\ntail\n' >> "$P/CLAUDE.md"
printf 'rule two\n' > "$RULES"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
EXPECTED="$(printf '# Mine\nkeep me\n\n%s\n## devlog-tracker 沉澱的規範\n\n- rule one\n- rule two\n%s\n\n## After\ntail' "$BEGIN_MARK" "$END_MARK")"
assert_eq "write: appended inside existing block" "$EXPECTED" "$(cat "$P/CLAUDE.md")"

# --- exact duplicates (existing + within input) skipped; file unchanged -------------
BEFORE="$(cat "$P/CLAUDE.md")"
printf -- '- rule one\nrule two\n' > "$RULES"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES")"
assert_eq "write: all duplicates" "ADDED=0 SKIPPED_DUP=2 TARGET=$P/CLAUDE.md" "$OUT"
assert_eq "write: file unchanged on all-dup" "$BEFORE" "$(cat "$P/CLAUDE.md")"
printf 'rule three\nrule three\n' > "$RULES"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES")"
assert_eq "write: duplicate within input counted once" "ADDED=1 SKIPPED_DUP=1 TARGET=$P/CLAUDE.md" "$OUT"

# --- symlink target: write-in-place preserves the link, rules land in the real file --
P="$(new_project)"
printf '# Base\n' > "$P/AGENTS.md"
ln -s AGENTS.md "$P/CLAUDE.md"
printf 'rule via symlink\n' > "$RULES"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
if [ -L "$P/CLAUDE.md" ]; then echo "PASS: write: symlink target stays a symlink"
else echo "FAIL: write: symlink was replaced by a regular file"; FAIL=1; fi
if grep -qF "rule via symlink" "$P/AGENTS.md"; then echo "PASS: write: rules land in the symlink's real target"
else echo "FAIL: write: rules missing from AGENTS.md"; FAIL=1; fi

# --- mode is preserved on a plain (non-symlink) target -------------------------------
P="$(new_project)"
printf '# Mode\n' > "$P/CLAUDE.md"
chmod 640 "$P/CLAUDE.md"
printf 'rule mode\n' > "$RULES"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
assert_eq "write: mode preserved (640)" "-rw-r-----" "$(ls -l "$P/CLAUDE.md" | cut -c1-10)"

# --- lock released ------------------------------------------------------------------
mkdir -p "$P/.devlog"
CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$RULES" >/dev/null
[ ! -e "$P/.devlog/.lock" ] && echo "PASS: write: lock released" || { echo "FAIL: write: .lock left behind"; FAIL=1; }

# --- usage errors ---------------------------------------------------------------------
bash "$SCRIPT_DIR/promote-write.sh" >/dev/null 2>&1
RC=$?
assert_eq "write: no args exits 2" "2" "$RC"
bash "$SCRIPT_DIR/promote-write.sh" "$P/CLAUDE.md" "$TMP_ROOT/missing.txt" >/dev/null 2>&1
RC=$?
assert_eq "write: missing rules file exits 2" "2" "$RC"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
