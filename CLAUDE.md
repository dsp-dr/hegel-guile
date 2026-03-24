## Your Role

You are a coding agent building hegel-guile. Write code, run tests, commit working increments. Do not plan without building.

## Foundational Axiom

Property-based testing is a protocol problem, not a library problem. The generation and shrinking engine (Hypothesis) runs once as a server process; each target language implements only the thin CBOR wire protocol client. Do not reimplement generation, shrinking, or search strategy at any layer of the stack.

## Confirmation Gate

Before writing any code, output a summary of: (1) which build step you are working on, (2) what its acceptance test is, (3) what files you will create or modify. Wait for confirmation before proceeding.

## What You Are Building

- A Guile 3 client for the [Hegel](https://hegel.dev) universal property-based testing protocol
- Communicates with `hegel-core` (Python/Hypothesis) over Unix sockets using length-prefixed CBOR frames
- Exposes a macro-based API (`define-hegel-test`, `tc-draw`, `tc-assume`) that feels native to Guile

## Explicit Anti-Goals

- **Not a PBT engine**: Do not implement generation, shrinking, or search. These live in `hegel-core`. Reimplementing them creates version drift and loses Hypothesis's decade of optimization.
- **Not a general CBOR library**: Only encode/decode types the protocol uses (maps, strings, integers, booleans, null, floats, arrays, bytevectors). Adding CBOR tags, indefinite-length encoding, or streaming would add complexity with zero protocol benefit.
- **Not a standalone framework**: The `(hegel test)` module requires a running `hegel-core` server. There is no "offline mode" — that would mean reimplementing the engine (see first anti-goal).
- **Not an SRFI-64 replacement**: `define-hegel-test` complements SRFI-64, it does not replace it. Unit tests stay in SRFI-64; property tests use Hegel.

## Key Design Decisions

- Alists as the universal map representation (not hash tables) — idiomatic Guile, easy to inspect in REPL
- Length-prefixed CBOR frames (uint32-BE header + payload) for message boundaries
- Client-side `gen-filter` and `gen-map` wrappers — server doesn't know about them, they use `tc-assume` for rejection
- `define-hegel-test` macro registers tests; `run-hegel-tests!` executes them all against a single server connection
- Server discovery: `HEGEL_SERVER_COMMAND` env var > `uv tool run hegel` > PATH lookup

## Wire Protocol Constraint

The client is a thin protocol adapter. All intelligence (data generation, shrinking, test case selection) lives in `hegel-core`. Per-component implications:

- **cbor.scm**: Encode/decode only. No schema validation, no CBOR extensions.
- **protocol.scm**: Message constructors produce alists. No retry logic, no buffering beyond what the port provides.
- **server.scm**: Spawn subprocess, read socket path from stdout, connect, handshake. No health monitoring, no reconnection.
- **test-case.scm**: `tc-draw` sends a draw request and returns the value. `tc-assume` sends assume and raises an exception. No caching, no local generation.
- **test.scm**: Loop over test cases, catch exceptions, report status. The server decides when to stop.

## Protocol Message Types

| Direction | Message | Key Fields |
|-----------|---------|------------|
| C→S | handshake | client, version |
| S→C | handshake | server_version |
| C→S | start_test | settings.test_cases |
| S→C | ok | — |
| C→S | start_test_case | — |
| C→S | draw | schema |
| S→C | value | value |
| C→S | assume | — |
| C→S | finish_test_case | status: passed/failed/invalid |
| C→S | finish_test | status: passed/failed |

## CBOR Type Coverage

| CBOR Major Type | Guile Representation | Used For |
|-----------------|---------------------|----------|
| 0 (uint) | exact integer ≥ 0 | counts, enum values |
| 1 (negint) | exact integer < 0 | negative test values |
| 2 (bytes) | bytevector | binary generator |
| 3 (text) | string | message types, keys |
| 4 (array) | list (non-alist) | schema elements |
| 5 (map) | alist | all messages |
| 7 (float/simple) | real / #t / #f / 'null | floats, booleans |

## Build Order

1. **CBOR codec** (`src/hegel/cbor.scm`) — Acceptance: `guile3 -L src tests/test-cbor.scm` passes all SRFI-64 tests
2. **Protocol client** (`src/hegel/protocol.scm`) — Acceptance: message constructors produce correct alists, response accessors extract fields
3. **Server manager** (`src/hegel/server.scm`) — Acceptance: `make-hegel-connection` spawns hegel-core, connects, completes handshake
4. **Test case** (`src/hegel/test-case.scm`) — Acceptance: `tc-draw` returns server-generated values, `tc-assume` raises on #f
5. **Generators** (`src/hegel/generators.scm`) — Acceptance: schema combinators produce correct alists, `gen-filter`/`gen-map` work client-side
6. **Test runner** (`src/hegel/test.scm`) — Acceptance: `define-hegel-test` registers tests, `run-hegel-tests!` executes all against server
7. **Top-level module** (`src/hegel.scm`) — Acceptance: `(use-modules (hegel))` re-exports full public API
8. **Examples** (`examples/basic.scm`) — Acceptance: runs end-to-end against hegel-core with 0 failures

If an acceptance test fails, stop. Document what failed, what you tried, and what the blocker is. Do not proceed to the next step. Surface the failure as a CPRR refutation candidate.

## Open Conjectures

- **C-001**: CBOR framing is length-prefixed uint32-BE. Falsification: capture hegel-rust ↔ hegel-core traffic with socat and inspect headers.
- **C-002**: Handshake is client-initiated. Falsification: server might send first (like HTTP/2 preface).
- **C-003**: Schema keys use snake_case. Status: confirmed by blog post example `{"type": "integers", "min_value": 100}`.
- **C-004**: `finish_test_case` status strings are "passed"/"failed"/"invalid". Falsification: server might use numeric codes.

## Instrumentation Requirement

Every conjecture must have a measurement hook. When implementing code that depends on a conjecture, add a check or assertion that would surface a violation. For example, if C-001 is wrong about framing, `cbor-decode-from-port` should produce a clear error, not corrupt data.

## Stack Preferences

- **Runtime**: guile3 (GNU Guile 3.x) — not guile, not guile2
- **Testing**: SRFI-64 for unit tests, Hegel for property tests
- **Build**: GNU Make
- **Module style**: `define-module` with `#:use-module` and `#:export`
- **Error handling**: `(ice-9 match)` for dispatch, `throw`/`catch` for control flow

## Acceptance: End-to-End Test

Run `guile3 -L src examples/basic.scm` with `hegel-core` installed. Expected:
1. Server spawns and prints socket path
2. Client connects and completes handshake
3. All 4 tests (commutative addition, number round-trip, title case idempotence, alist model) run with 0 failures
4. Exit code 0

This is the system's definition of done.
