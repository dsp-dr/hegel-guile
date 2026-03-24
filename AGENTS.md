# Agent Coordination

## Worktree Agents

Use `sb` (worktree manager) to spin up isolated worktrees for parallel work:

```bash
sb create <branch-name>   # create worktree
sb list                    # show active worktrees
sb remove <branch-name>   # clean up
```

## Research vs Implementation

- **Research agents** run in worktrees and produce findings (no commits to main)
- **Implementation agents** work on the main worktree and commit to feature branches
- Never have two agents writing to the same branch

## Conjecture Tracking

All agents must use `cprr` for conjecture lifecycle:

```bash
cprr add "<claim>" --hypothesis "<falsification>"
cprr list
cprr refute <id> --evidence "<what happened>"
cprr confirm <id> --evidence "<what proved it>"
```

## Issue Tracking

Use `bd` for issue management:

```bash
bd ready          # show next actionable issue
bd start <id>     # begin work on an issue
bd done <id>      # mark complete
bd create "title" --description="desc" -t feature -p 1
```

## Build & Test

```bash
guile3 -L src tests/test-cbor.scm    # unit tests
guile3 -L src examples/basic.scm     # end-to-end (needs hegel-core)
make test                             # compile + unit tests
make compile                          # compile all modules
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
