#!/usr/bin/env bash
# Fail if tracked (or staged) files contain something that looks like a credential.
# Usage: scripts/secret-scan.sh [--staged]
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ "${1:-}" = "--staged" ]; then
  files=$(git diff --cached --name-only --diff-filter=ACMR)
else
  files=$(git ls-files)
fi

# Literal provider keys / tokens, plus any non-placeholder api_key in TOML
PATTERN='(sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|Bearer [A-Za-z0-9._-]{24,}|api_key[[:space:]]*=[[:space:]]*"[^"$]{8,}")'

status=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    scripts/secret-scan.sh | tests/test_*.lua | *.dll) continue ;;
  esac
  if [ "${1:-}" = "--staged" ]; then
    hits=$(git show ":$f" | grep -nEI -e "$PATTERN" || true)
  else
    hits=$(grep -nEI -e "$PATTERN" -- "$f" || true)
  fi
  if [ -n "$hits" ]; then
    # Show location only, never the matched secret
    echo "possible secret in $f (lines: $(echo "$hits" | cut -d: -f1 | paste -sd, -))" >&2
    status=1
  fi
done <<< "$files"

if [ "$status" -ne 0 ]; then
  echo "secret-scan: FAILED. Use \${ENV_VAR} placeholders; rotate any key that was committed." >&2
fi
exit "$status"
