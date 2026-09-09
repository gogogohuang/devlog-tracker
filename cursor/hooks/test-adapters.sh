#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
mkdir -p "$TMP/project/.devlog"
cat > "$TMP/project/.devlog/devlog.md" <<'EOF'
## Round 1 — now

### Summary
done

### Handoff
#### 現況
done

### Status
DONE
EOF
OUT="$(printf '{"workspace_roots":["%s"]}' "$TMP/project" | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$OUT" in *'"additional_context"'*"Round 1"*) echo "PASS: sessionStart context" ;; *) echo "FAIL: sessionStart [$OUT]"; FAIL=1 ;; esac
EMPTY="$(printf '{}' | bash "$SCRIPT_DIR/on-session-start.sh")"
case "$EMPTY" in \{*\}) echo "PASS: empty workspace valid json" ;; *) echo "FAIL: empty json [$EMPTY]"; FAIL=1 ;; esac

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
