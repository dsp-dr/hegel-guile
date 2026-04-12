# Property Cages from guile-sage

This is a record of three property cages that were first written
in [`dsp-dr/guile-sage`](https://github.com/dsp-dr/guile-sage) using
an ad-hoc PBT harness, and then ported here as canonical hegel-guile
examples. They are general patterns that come up in any Scheme
codebase that crosses an FFI / JSON / serialisation / filesystem
boundary, and they are exactly the kind of property test that
benefits from Hypothesis's shrinking — the failure modes are
non-obvious counterexamples that ad-hoc PRNG harnesses don't
minimise.

## Background

In the 0.6.0 release cycle of guile-sage, three real production
bugs surfaced via property tests:

1. **Streaming tool_calls vanished** because `ollama-parse-tool-call`
   accepted only `vector?` while the JSON parser returned `list?`.
2. **`read_logs` crashed with `wrong-type-arg`** when the LLM
   emitted `"lines": "20"` (string) instead of `"lines": 20`
   (integer), and `(min "20" 50)` blew up.
3. **`write_file` lied about where it wrote files** — given
   `/tmp/foo` it silently wrote to `<workspace>/tmp/foo` but
   echoed `Wrote N bytes to /tmp/foo` verbatim.

The fixes (centralised helpers `as-list`, `coerce->int`,
`resolve-path`) were validated with property tests in
[`tests/test-pbt.scm`](https://github.com/dsp-dr/guile-sage/blob/main/tests/test-pbt.scm).
Each property is a small invariant that pins the contract of
the helper. They aren't sage-specific.

## What was ported

| Sage commit / bd | Hegel example | Properties | Trials |
|---|---|---|---|
| [`15c7960` / guile-p94](https://github.com/dsp-dr/guile-sage/commit/15c7960) | [`examples/shape-coercion.scm`](../examples/shape-coercion.scm) | 4 | ~750 |
| [`769da88` / guile-bcy](https://github.com/dsp-dr/guile-sage/commit/769da88) | [`examples/json-int-fuzz.scm`](../examples/json-int-fuzz.scm) | 6 | ~2300 |
| [`728bcc4` / guile-ecn](https://github.com/dsp-dr/guile-sage/commit/728bcc4) | [`examples/file-roundtrip.scm`](../examples/file-roundtrip.scm) | 4 | ~350 |

Each example file:
- Includes the bug story in its header comment so the property is
  motivated rather than abstract.
- Uses `define-hegel-test` and `tc-draw` from the existing
  `(hegel)` module, mirroring the structure of `examples/basic.scm`.
- Contains both the helper-under-test and the properties so the
  file is self-contained and runnable as `guile3 -L src
  examples/<file>.scm`.

## Why these patterns are general

### Shape coercion

Any Scheme code that gets data from an external source (JSON
parser, FFI, deserializer) and that data includes "arrays" will
hit the vector-vs-list ambiguity. The only sane fix is a single
defensive coercion helper at the boundary, then the rest of the
code only ever sees one shape. The property cage is the contract
of that helper.

### JSON int-arg fuzzing

Any Scheme code that consumes LLM-emitted tool args has to defend
against the model's inconsistent JSON int encoding. This is not
a sage-specific problem; it bites every project building tools
for LLMs. The cage tests 7 input shapes and includes the
`(integer? 20.0)` Guile gotcha as a teaching moment for the
naive coercion attempt.

### Filesystem honesty

Any helper that takes a path and writes a file should report the
ACTUAL location, not the input path. This is a generic "the
output of an action must reflect the action that was taken"
property — it would catch a class of "lying tool" bugs that go
beyond filesystem helpers.

## Origin repo cross-references

- guile-sage `tests/test-pbt.scm` — the original ad-hoc harness
  with all 61 properties (6100 trials total at seed 42)
- guile-sage `docs/UX-FINDINGS-0.6.0.md` — the exploratory UX
  testing session that surfaced the bugs these cages catch
- guile-sage `docs/MCP-CONTRACT.org` — the MCP protocol research
  doc that motivated the {} sentinel and as-list helper extraction
- guile-sage `src/sage/util.scm` — the canonical home of the
  helpers in their production form

## Related hegel-guile issues

- `hegel-guile-16` — examples/shape-coercion.scm (closed)
- `hegel-guile-17` — examples/json-int-fuzz.scm (closed)
- `hegel-guile-18` — examples/file-roundtrip.scm (closed)
- `hegel-guile-19` — `bd init` fails because `beads_hegel-guile`
  contains a dash (open; needs metadata.json fix)

## Related hegel-guile work this builds alongside

- `tests/test-crc32-pbt.scm`, `tests/test-cbor-pbt.scm`,
  `tests/test-packet-pbt.scm`, `tests/test-generators-pbt.scm`
  are the existing PBT property tests that test the protocol
  layer (CRC32, CBOR, HEGL packet framing, schema generators).
  The new examples added here cover a *different layer*: generic
  Scheme defensive patterns at FFI / JSON / filesystem
  boundaries. Complementary, not overlapping.
- `docs/pbt-landscape.md` is the existing Scheme PBT ecosystem
  research doc. The cages here are concrete examples of the
  patterns that doc surveys.
- The `C9 gap` issue series (`hegel-guile-8` through `15`) is
  protocol-layer remediation and is unrelated to this
  cross-pollination.

## Future cross-pollination candidates

These patterns from sage's PBT suite would also port well:

- **Telemetry counter normalisation** — `normalize-labels` is
  sorted-by-key and idempotent. Property: any permutation of
  equivalent inputs produces the same output.
- **Model fallback selection** — `select-fallback-model` never
  returns an embedding/image model and always returns the
  smallest chat-capable element. Property: filter and order
  invariants for any "pick best from list" function.
- **OTLP `{}` empty-object encoding** — sage's
  `json-empty-object` sentinel + writer clause. Property: the
  sentinel always serialises to literal `{}` regardless of
  nesting depth.

When the hegel-guile ecosystem grows enough to need its own
tool-calling layer or its own filesystem helpers, these are the
properties to bring.
