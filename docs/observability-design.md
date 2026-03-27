Now I have the full picture. Here is the design document.

---

## Design: Observability Layer for hegel-guile

### Problem Statement

Debugging hegel-guile requires visibility into the wire traffic between the Guile client and hegel-core. Currently there is no way to observe packets, decode messages, or trace the request/reply lifecycle without attaching an external tool (socat, strace). The system needs an in-process observability layer that adheres to the thin-client philosophy: no intelligence, no buffering beyond what already exists, just a place to hook a lamp.

### Architecture Context

The current stack, bottom to top:

```
Unix socket (in-port / out-port)
  |
packet.scm     -- read-hegl-packet! / write-hegl-packet!  (framing, CRC32)
  |
mux.scm        -- connection-mux  (demux by channel-id, per-channel buffering)
  |
channel.scm    -- channel-send-request! / channel-recv-reply!  (CBOR envelope)
  |
test-case.scm  -- tc-draw / tc-assume  (protocol commands)
  |
test.scm       -- event loop  (run_test lifecycle)
```

The mux is the natural observation point. It is the single funnel through which all post-handshake traffic flows. Every packet passes through either `mux-read-for-channel!` or `mux-write-packet!`. The handshake (pre-mux, direct mode) is a special case handled separately.

### Approach Comparison

| Criterion | A: Transport Proxy | B: Packet Observer (Mux Wrapper) | C: Call-Site Instrumentation | D: Guile Soft Port |
|---|---|---|---|---|
| **Observation granularity** | Raw bytes | Decoded packets (channel-id, message-id, CBOR payload) | Semantic commands (generate, mark_complete) | Raw bytes |
| **Code changes required** | 1 line in server.scm (wrap ports) | 1 line in server.scm (wrap mux) | Every call site (~8 locations) | 1 line in server.scm (wrap ports) |
| **Coupling** | None above transport | Coupled to `<connection-mux>` interface (2 procedures) | Coupled to every protocol operation | None above transport |
| **CBOR visibility** | No (must decode externally) | Yes (can decode in observer callback) | Yes (implicit -- sees Scheme values) | No |
| **Channel-id visibility** | No (buried in binary) | Yes (first-class field on every packet) | Only what the call site knows | No |
| **Performance when disabled** | Zero (don't wrap) | Zero (don't wrap) | Conditional branch per call site | Zero (don't wrap) |
| **Performance when enabled** | Byte-copy overhead | CBOR decode + callback overhead | Callback overhead per operation | Soft port dispatch overhead |
| **Handshake visibility** | Yes (all bytes) | Partial (pre-mux traffic is direct) | Yes (if you instrument `perform-handshake`) | Yes (all bytes) |
| **Distributed systems analog** | Envoy sidecar | gRPC interceptor / Ring middleware | OpenTelemetry library instrumentation | eBPF / ktrace |
| **Thin-client fit** | Good -- no semantic knowledge | Best -- observes the protocol boundary without adding logic | Poor -- scatters instrumentation, tempts adding retry/metrics | Good but wrong granularity |

### Recommendation: Approach B (Packet-Level Observer Wrapping Mux)

Rationale:

1. **The mux is the waist of the hourglass.** All post-handshake traffic funnels through two procedures: `mux-read-for-channel!` and `mux-write-packet!`. Wrapping these gives complete coverage with a single interception point.

2. **Packet-level is the right granularity.** The observer sees channel-id, message-id, reply-bit, and the raw payload (which it can optionally CBOR-decode). This is the same level of detail you would get from a Wireshark dissector for the HEGL protocol. Byte-level (A, D) is too low; semantic-level (C) requires scattered instrumentation.

3. **The mux interface is stable and small.** It exposes exactly two operations for traffic flow. If the interface changes, the observer breaks loudly at compile time -- not silently like scattered call-site instrumentation.

4. **Zero cost when disabled.** If you do not wrap the mux, no observer code runs. No conditional branches at call sites, no environment variable checks in hot paths.

5. **Handles the handshake gap cleanly.** The handshake is 2 packets on a direct channel before the mux exists. The observer module can export a separate `observe-handshake!` hook that `perform-handshake` calls. This is 1 additional call site, not 8.

### API Sketch: `(hegel observe)` module

```scheme
(define-module (hegel observe)
  #:use-module (hegel mux)
  #:use-module (hegel packet)
  #:use-module (hegel cbor)
  #:use-module (srfi srfi-9)
  #:export (make-observed-mux
            observed-mux?
            observed-mux-inner

            ;; Observer callback protocol
            make-packet-observer
            packet-observer?
            packet-observer-on-read
            packet-observer-on-write

            ;; Built-in observers
            make-logging-observer
            make-file-observer
            make-null-observer

            ;; Handshake observation (pre-mux)
            observe-handshake-send!
            observe-handshake-recv!))
```

**Core type: `<observed-mux>`**

A record wrapping `<connection-mux>` that delegates all operations to the inner mux but calls observer callbacks before/after each read and write.

```scheme
(define-record-type <observed-mux>
  (%make-observed-mux inner observer)
  observed-mux?
  (inner    observed-mux-inner)
  (observer observed-mux-observer))
```

The observed-mux must satisfy the same interface as `<connection-mux>`. Since channel.scm calls `mux-read-for-channel!` and `mux-write-packet!` via generic dispatch (it checks `(hegel-channel-mux channel)` and calls the mux procedures directly), the observed-mux needs to be usable anywhere a connection-mux is used.

Two implementation strategies for polymorphism:

**(i) Wrapper procedures passed to channels.** Redefine `mux-read-for-channel!` and `mux-write-packet!` to check if the mux is an `<observed-mux>` and dispatch accordingly. This requires modifying mux.scm to add the type check.

**(ii) Duck-type via closure.** Instead of a record, the observed-mux is a pair of closures (read-proc, write-proc) that close over the inner mux and the observer. Channel.scm would need to call these closures instead of the mux procedures.

Strategy (i) is cleaner. The type check in mux.scm is 4 lines and keeps the dispatch centralized.

**Observer callback protocol:**

```scheme
(define-record-type <packet-observer>
  (make-packet-observer on-read on-write)
  packet-observer?
  (on-read  packet-observer-on-read)    ; (lambda (direction channel-id packet decoded-or-#f) ...)
  (on-write packet-observer-on-write))  ; (lambda (direction channel-id packet decoded-or-#f) ...)
```

Both callbacks receive:
- `direction` -- symbol `'read` or `'write`
- `channel-id` -- integer, extracted from the packet
- `packet` -- the `<hegl-packet>` record
- `decoded` -- the CBOR-decoded payload as a Scheme value, or `#f` if decoding is disabled or fails (raw handshake bytes are not CBOR)

The observer never throws. If the callback raises, the observer catches and logs the error to `(current-error-port)`. Observation must not break the protocol.

**Built-in observers:**

`make-logging-observer` -- writes one line per packet to `(current-error-port)`:

```
[hegel] WRITE ch=0 msg=1 bytes=24 {"command":"run_test","channel_id":1,"test_cases":100}
[hegel]  READ ch=0 msg=1|R bytes=12 {"result":true}
[hegel]  READ ch=1 msg=1 bytes=38 {"event":"test_case","channel_id":3}
[hegel] WRITE ch=1 msg=1|R bytes=6 {"result":null}
```

`make-file-observer` -- writes NDJSON to a file descriptor, one JSON object per packet. Useful for post-hoc analysis.

`make-null-observer` -- no-op callbacks. Exists so code can unconditionally wrap the mux and pay no cost.

### Integration with Existing Code

**Changes to `server.scm` (the only structural change):**

In `make-hegel-connection`, after creating the mux and before creating the muxed control channel, conditionally wrap:

```scheme
;; After: (mux (make-connection-mux in-port out-port))
;; Add:
(let* ((raw-mux (make-connection-mux in-port out-port))
       (mux     (if (observer-enabled?)
                    (make-observed-mux raw-mux (current-observer))
                    raw-mux))
       (control (make-muxed-channel 0 mux)))
  ...)
```

This is 3 changed lines. No other file changes.

**Changes to `mux.scm` (dispatch extension):**

`mux-read-for-channel!` and `mux-write-packet!` gain a type check:

```scheme
(define (mux-read-for-channel! mux channel-id)
  (if (observed-mux? mux)
      (observed-mux-read-for-channel! mux channel-id)
      (%mux-read-for-channel! mux channel-id)))
```

Where `%mux-read-for-channel!` is the current implementation renamed. The observed variant delegates to the inner mux and calls the observer callback.

**No changes to:** channel.scm, protocol.scm, test-case.scm, test.scm, cbor.scm, packet.scm.

### Enabling/Disabling

Three mechanisms, checked in order:

1. **Environment variable `HEGEL_DEBUG`** -- `HEGEL_DEBUG=1` enables the logging observer to stderr. `HEGEL_DEBUG=file:/tmp/hegel.ndjson` enables the file observer. This is the primary interface for users.

2. **Programmatic API** -- `(set-current-observer! observer)` for custom observers. Called before `make-hegel-connection`. This is for test harnesses and REPL exploration.

3. **Module import** -- if `(hegel observe)` is never imported and `HEGEL_DEBUG` is unset, the observer code is never loaded. The mux type check in mux.scm uses a late-bound predicate: `observed-mux?` is `#f`-returning until `(hegel observe)` is loaded. This avoids a hard dependency from mux.scm on observe.scm.

Implementation of the late binding:

```scheme
;; In mux.scm:
(define *observed-mux-dispatch* #f)  ; set by (hegel observe) on load

(define (mux-read-for-channel! mux channel-id)
  (if (and *observed-mux-dispatch*
           (not (connection-mux? mux)))
      ((*observed-mux-dispatch* 'read) mux channel-id)
      (%mux-read-for-channel! mux channel-id)))
```

This avoids a circular dependency: mux.scm does not import observe.scm; observe.scm imports mux.scm and registers itself.

### Handshake Observation

The handshake occurs before the mux exists (lines 137-139 of server.scm). Two raw packets: client sends `"hegel_handshake_start"`, server replies `"Hegel/0.7"`. To observe these:

`perform-handshake` gains an optional observer parameter. If present, it calls `observe-handshake-send!` and `observe-handshake-recv!` with the raw bytevectors. These are thin wrappers that format and call the observer's callbacks with `channel-id=0` and `decoded=#f` (since the handshake is not CBOR).

This is 2 additional lines in `perform-handshake`, gated on the observer being non-`#f`.

### What This Does Not Do

- No retry logic. If the observer callback takes too long, the protocol stalls. That is correct: observation should be fast.
- No filtering. Every packet is observed. Filtering by channel-id or message type is the observer callback's responsibility.
- No persistence beyond the file observer. No database, no metrics aggregation. Those are downstream consumers of the NDJSON output.
- No modification of packets. The observer is read-only. It cannot alter, drop, or inject packets. A future "middleware" pattern could extend this, but that violates the thin-client constraint today.

### Conjectures Introduced

- **C-015**: The `<observed-mux>` late-binding dispatch adds negligible overhead when `(hegel observe)` is not loaded. Falsification: benchmark `mux-read-for-channel!` with and without the `*observed-mux-dispatch*` check in a tight loop. The branch predictor should make this free.
- **C-016**: CBOR decoding in the observer callback does not measurably affect protocol throughput. Falsification: run 10,000 test cases with and without the logging observer enabled. If wall-clock time increases by more than 5%, the decode should be made lazy or opt-in.

### File Inventory

| File | Status | Purpose |
|---|---|---|
| `src/hegel/observe.scm` | **New** | Observer types, built-in observers, late-bind registration |
| `src/hegel/mux.scm` | **Modified** | Add `*observed-mux-dispatch*` slot, rename internals with `%` prefix |
| `src/hegel/server.scm` | **Modified** | Conditional mux wrapping in `make-hegel-connection`, observer param on `perform-handshake` |
| All other files | **Unchanged** | -- |

### Relationship to Distributed Systems Patterns

The recommended approach most closely resembles **gRPC interceptors** or **Ring middleware**: a wrapper at a well-defined interface boundary that observes traffic without participating in it. It is not a sidecar (that would be an external process like socat), not library instrumentation (that would scatter `observe!` calls everywhere), and not kernel tracing (that would operate on raw bytes below the protocol layer).

The key insight from distributed systems: **observe at the narrowest interface with the richest structure**. For hegel-guile, that interface is the mux. It is the single point where all channels converge, and every packet passing through it carries structured metadata (channel-id, message-id, reply-bit, typed payload).