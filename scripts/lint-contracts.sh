#!/bin/sh
# lint-contracts.sh — Verify module contracts and structural invariants
# Exit 0 if clean, 1 if issues found

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

# --- Check: no circular imports between hegel/* modules ---
echo "Checking for circular imports..."
for f in "$REPO_ROOT"/src/hegel/*.scm; do
    mod=$(basename "$f" .scm)
    # Find modules this file imports from (hegel ...)
    imports=$(grep '#:use-module (hegel ' "$f" 2>/dev/null | sed 's/.*#:use-module (hegel \([^)]*\)).*/\1/' || true)
    for dep in $imports; do
        # Check if dep imports mod back
        dep_file="$REPO_ROOT/src/hegel/$dep.scm"
        if [ -f "$dep_file" ] && grep -q "#:use-module (hegel $mod)" "$dep_file" 2>/dev/null; then
            echo "  CIRCULAR: hegel/$mod.scm <-> hegel/$dep.scm"
            ERRORS=$((ERRORS + 1))
        fi
    done
done

# --- Check: every test file has a matching source module ---
echo "Checking test-to-source mapping..."
for f in "$REPO_ROOT"/tests/test-*.scm; do
    base=$(basename "$f" .scm)
    # Strip test- prefix; handle test-X-pbt -> X
    mod=$(echo "$base" | sed 's/^test-//; s/-pbt$//')
    src="$REPO_ROOT/src/hegel/$mod.scm"
    if [ ! -f "$src" ]; then
        # Try with hyphen variants (test-test-case -> test-case)
        echo "  WARN: no src/hegel/$mod.scm for tests/$base.scm"
    fi
done

# --- Check: hegel.scm re-exports cover all submodules ---
echo "Checking hegel.scm re-export coverage..."
TOP="$REPO_ROOT/src/hegel.scm"
for f in "$REPO_ROOT"/src/hegel/*.scm; do
    mod=$(basename "$f" .scm)
    # Skip internal modules that are transitive deps (not directly re-exported)
    # hegel.scm uses (hegel generators) and (hegel test) which pull in the rest
    # We check that every module is reachable via the import chain
    if ! grep -q "(hegel $mod)" "$TOP" 2>/dev/null; then
        # Check if it's a transitive dep of an imported module
        is_transitive=0
        for imported in $(grep '#:use-module (hegel ' "$TOP" 2>/dev/null | sed 's/.*#:use-module (hegel \([^)]*\)).*/\1/'); do
            imp_file="$REPO_ROOT/src/hegel/$imported.scm"
            if [ -f "$imp_file" ] && grep -q "(hegel $mod)" "$imp_file" 2>/dev/null; then
                is_transitive=1
                break
            fi
            # Check second-level transitive deps
            for dep2 in $(grep '#:use-module (hegel ' "$imp_file" 2>/dev/null | sed 's/.*#:use-module (hegel \([^)]*\)).*/\1/'); do
                dep2_file="$REPO_ROOT/src/hegel/$dep2.scm"
                if [ -f "$dep2_file" ] && grep -q "(hegel $mod)" "$dep2_file" 2>/dev/null; then
                    is_transitive=1
                    break 2
                fi
                # Third level
                for dep3 in $(grep '#:use-module (hegel ' "$dep2_file" 2>/dev/null | sed 's/.*#:use-module (hegel \([^)]*\)).*/\1/'); do
                    dep3_file="$REPO_ROOT/src/hegel/$dep3.scm"
                    if [ -f "$dep3_file" ] && grep -q "(hegel $mod)" "$dep3_file" 2>/dev/null; then
                        is_transitive=1
                        break 3
                    fi
                done
            done
        done
        if [ "$is_transitive" -eq 0 ]; then
            echo "  MISSING re-export: hegel/$mod.scm not reachable from hegel.scm"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

if [ "$ERRORS" -gt 0 ]; then
    echo "lint-contracts: $ERRORS issue(s) found"
    exit 1
else
    echo "lint-contracts: OK"
    exit 0
fi
