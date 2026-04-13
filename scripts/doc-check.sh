#!/bin/sh
# doc-check.sh — Verify documentation covers all source modules
# Exit 0 if clean, 1 if issues found

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

# --- Check: every src/hegel/*.scm module appears in CLAUDE.md ---
echo "Checking CLAUDE.md module coverage..."
for f in "$REPO_ROOT"/src/hegel/*.scm; do
    base=$(basename "$f")
    if ! grep -q "$base" "$REPO_ROOT/CLAUDE.md"; then
        echo "  MISSING in CLAUDE.md: hegel/$base"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Check: every src/hegel/*.scm module appears in README.org ---
echo "Checking README.org module coverage..."
for f in "$REPO_ROOT"/src/hegel/*.scm; do
    base=$(basename "$f")
    if ! grep -q "$base" "$REPO_ROOT/README.org"; then
        echo "  MISSING in README.org: hegel/$base"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Check: no hardcoded IPs in docs ---
echo "Checking for hardcoded IPs in docs..."
for doc in "$REPO_ROOT"/docs/*.org "$REPO_ROOT"/docs/*.md "$REPO_ROOT"/README.org; do
    [ -f "$doc" ] || continue
    if grep -Pn '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' "$doc" 2>/dev/null | grep -v '0\.0\.0\.0\|127\.0\.0\.1\|localhost' | grep -v '^$' >/dev/null 2>&1; then
        echo "  HARDCODED IP in $(basename "$doc"):"
        grep -Pn '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' "$doc" | grep -v '0\.0\.0\.0\|127\.0\.0\.1\|localhost' | sed 's/^/    /'
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -gt 0 ]; then
    echo "doc-check: $ERRORS issue(s) found"
    exit 1
else
    echo "doc-check: OK"
    exit 0
fi
