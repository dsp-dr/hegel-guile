#!/bin/sh
# health-check.sh — Validate project scaffold integrity
# Exit codes: 0=ok, 1=degraded, 2=broken

set -e

STATUS=0
HARD_FAILS=""
SOFT_FAILS=""

check_hard() {
    if ! eval "$2" >/dev/null 2>&1; then
        HARD_FAILS="${HARD_FAILS}  - $1\n"
        STATUS=2
    fi
}

check_soft() {
    if ! eval "$2" >/dev/null 2>&1; then
        SOFT_FAILS="${SOFT_FAILS}  - $1\n"
        [ "$STATUS" -lt 1 ] && STATUS=1
    fi
}

# Hard checks (STATUS=2 if any fail)
check_hard "git repo"       "git rev-parse --git-dir"
check_hard "spec.org"       "test -f spec.org"
check_hard "CLAUDE.md"      "test -f CLAUDE.md"
check_hard "AGENTS.md"      "test -f AGENTS.md"
check_hard "cprr store"     "cprr list"
check_hard "git remote"     "git remote get-url origin"
check_hard "src directory"  "test -d src/hegel"

# Soft checks (STATUS=1 if any fail)
check_soft "bd server"      "bd status"
check_soft "bd ready"       "bd ready"
check_soft "sb doctor"      "sb doctor"
check_soft "guile3"         "guile3 --version"
check_soft "uv"             "uv --version"

# Output JSON
printf '{\n'
printf '  "status": %d,\n' "$STATUS"
printf '  "status_text": "%s",\n' "$([ $STATUS -eq 0 ] && echo ok || ([ $STATUS -eq 1 ] && echo degraded || echo broken))"

if [ -n "$HARD_FAILS" ]; then
    printf '  "hard_failures": [\n'
    printf "$HARD_FAILS" | sed 's/^  - /    "/;s/$/",/' | sed '$ s/,$//'
    printf '\n  ],\n'
else
    printf '  "hard_failures": [],\n'
fi

if [ -n "$SOFT_FAILS" ]; then
    printf '  "soft_failures": [\n'
    printf "$SOFT_FAILS" | sed 's/^  - /    "/;s/$/",/' | sed '$ s/,$//'
    printf '\n  ],\n'
else
    printf '  "soft_failures": [],\n'
fi

printf '  "timestamp": "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '}\n'

exit $STATUS
