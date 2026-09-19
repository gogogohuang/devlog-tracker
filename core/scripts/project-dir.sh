#!/usr/bin/env bash
# Sourced helper: the single documented definition of "which project
# directory is a hook/script operating in". Precedence:
#   1. DEVLOG_PROJECT_DIR — neutral name, harness-agnostic
#   2. CLAUDE_PROJECT_DIR — Claude Code's own variable, kept as a
#      compatibility fallback so anything that already exports it
#      (Claude Code itself, or an external script) keeps working
#      unmodified
#   3. "." — current directory, when neither is set
#
# Most core/scripts/*.sh scripts inline the equivalent expression
# (`${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}`) directly rather than
# sourcing this file, to keep each entry-point script a single self-
# contained line. This file is the canonical statement of that precedence
# and is exercised by core/scripts/tests/test-project-dir.sh; source it
# instead of re-deriving the fallback chain in new code.
devlog_project_dir() {
  printf '%s\n' "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
}
