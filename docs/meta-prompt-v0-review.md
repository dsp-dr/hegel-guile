# Meta-Prompt v0 Self-Review

## Critical Checklist

- [x] Agent role is stated explicitly (coding, not planning) — line 1: "You are a coding agent"
- [x] Build order has failure handler text — present after step 8
- [x] Conjectures have instrumentation requirement — dedicated section present
- [x] Axiom appears before line 10 — line 5 (## Foundational Axiom)

## Substantive Checklist

- [x] Confirmation gate is present — line 9
- [x] Anti-goals state mechanical failure modes — each bullet explains *why* it fails
- [x] Architectural constraints are named sections — "Wire Protocol Constraint" is a named section
- [x] Success criteria are testable assertions — end-to-end test has 4 specific assertions
- [x] No "low relevance" links included — no external links beyond hegel.dev

## Minor Notes

- [ ] hegel.dev URL may need vendoring if offline work is expected
- [ ] Assumes `uv` is installed for `uv tool run hegel` — documented in server discovery chain
- [ ] Assumes Unix sockets (AF_UNIX) — no Windows support, which is fine for Guile 3

## Result

All critical and substantive items pass. v0 promoted to v1 (live CLAUDE.md) without changes.
