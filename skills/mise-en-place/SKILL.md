---
name: mise-en-place
description: Verify workspace prerequisites before development. Triggers on: "mise-en-place", "setup", "check environment", "preflight", "workspace check", "dev setup", "verify prerequisites"
---

# Mise en Place

Everything in its place before you cook.

Verify the workspace is ready for hegel-guile development. Run these checks
in order — stop at the first failure and tell the user what to fix.

## Checks

### 1. Guile 3.x

```sh
${GUILE:-guile} --version 2>/dev/null | head -1
```

Expect `GNU Guile` with version `3.x`. If missing: `brew install guile` (macOS),
`sudo apt install guile-3.0` (Debian/Ubuntu), `pkg install guile3` (FreeBSD).

Verify guild is also present:

```sh
${GUILD:-guild} --version 2>/dev/null | head -1
```

### 2. Python 3.11+

```sh
python3 --version
```

Needed for hegel-core. If using asdf/mise, `.tool-versions` pins `python 3.11.11`.

### 3. hegel-core

```sh
hegel --version 2>/dev/null || uv tool run hegel --version 2>/dev/null
```

Expect `0.2.x`. If missing:

```sh
uv tool install hegel-core==0.2.3
# or
pip install hegel-core==0.2.3
```

Version must be `~0.2.x` — hegel-guile 0.7.x is tested against this range.

### 4. GNU Make

```sh
gmake --version 2>/dev/null || make --version 2>/dev/null
```

Must be GNU Make, not BSD make. On FreeBSD use `gmake`.

### 5. Compilation

```sh
gmake compile 2>&1 || make compile 2>&1
```

All modules must compile without errors.

### 6. Unit Tests

```sh
gmake test 2>&1 || make test 2>&1
```

All SRFI-64 tests must pass.

### 7. Integration (optional)

Only if hegel-core is installed:

```sh
${GUILE:-guile} -L src examples/basic.scm
```

Known issue: hangs at 200+ test cases (hegel-guile-15). Pass at low case counts
confirms the protocol stack is wired correctly.

## Output

Report a table:

| Check | Status | Detail |
|-------|--------|--------|
| Guile | pass/fail | version |
| Python | pass/fail | version |
| hegel-core | pass/fail/skip | version |
| GNU Make | pass/fail | path |
| Compile | pass/fail | error count |
| Unit Tests | pass/fail | pass/fail/skip counts |
| Integration | pass/fail/skip | — |

If all required checks pass, say the kitchen is ready.
