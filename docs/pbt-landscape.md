Now I have a comprehensive picture. Here is the structured report.

---

## Property-Based Testing in Guile and the Broader Scheme Ecosystem

### Research Report

---

### 1. GUILE-SPECIFIC PBT LIBRARIES

#### 1.1 guile-quickcheck

- **URL**: https://ngyro.com/software/guile-quickcheck.html / https://git.ngyro.com/guile-quickcheck
- **Guix package**: https://guix.gnu.org/packages/guile-quickcheck-0.1.0/
- **Scheme**: GNU Guile (3.x compatible)
- **Version**: 0.1.0 (released 2021-03-01)
- **Status**: Dormant. Single release, no visible activity since 2021. Copyright header extends to 2025 but no subsequent releases.
- **License**: GPL-3.0
- **Author**: ngyro (Timothy Sample, a Guix contributor)

**API style**: Haskell QuickCheck-inspired with Racket influence. Generators use the `$` prefix convention (read as "arbitrary"): `$const`, `$choose`, `$list`. Properties defined via a `property` form with let-style bindings. Tests invoked with `quickcheck`.

**Generators**: Limited documented set -- `$const`, `$choose`, `$list`. No evidence of numeric generators (`$integer`, `$real`), string generators, or other type-specific primitives in the public documentation.

**Shrinking**: No evidence of shrinking support in any documentation or description.

**Key limitation**: Extremely thin documentation -- one pizza-topping example on the website. No API reference. No evidence of real-world adoption beyond Guix packaging. The generator combinator library appears minimal compared to Racket or Haskell QuickCheck.

**Relationship to hegel-guile**: guile-quickcheck is a local-generation monolithic PBT library. All generation and search happen in-process in Guile. It does not benefit from Hypothesis's decade of engine optimization, has no shrinking, and its generator library is sparse. hegel-guile delegates all generation/shrinking to hegel-core via the wire protocol, inheriting the full power of Hypothesis.

---

#### 1.2 Guile Proba

- **URL**: https://luis-felipe.gitlab.io/guile-proba/
- **Scheme**: GNU Guile
- **Version**: 0.3.1
- **Status**: Maintained (available in Guix channels)
- **License**: Public domain

**What it is**: A test runner/discovery tool for SRFI-64-based test suites. Automatically discovers and runs tests in project directories. Provides CLI (`proba run tests`) and programmatic API via `(proba commands)`.

**PBT support**: None. This is a test runner, not a property testing framework. Included here for completeness since it appeared in Guile testing searches.

---

#### 1.3 Veritas

- **URL**: https://codeberg.org/jjba23/veritas
- **Scheme**: GNU Guile
- **Status**: Active (packaged as guile-veritas in Guix)
- **Author**: jjba23

**What it is**: A unit, integration, and black box testing framework. Features include test auto-discovery, concurrent test execution, order randomization, and benchmarking via statprof.

**PBT support**: None. This is a test framework, not a property testing system. No generation, no shrinking, no property combinators.

---

### 2. SCHEME-WIDE PBT LIBRARIES

#### 2.1 SRFI-252: Property Testing

- **URL**: https://srfi.schemers.org/srfi-252/
- **Scheme**: Portable (R7RS). Currently implemented for Chicken 5.
- **Status**: **Final** (finalized 2024-04-25). This is the most significant development in Scheme PBT.
- **Author**: Antero Mejr
- **License**: MIT (SRFI standard)

**Design**: Extends SRFI-64 test suite API for property testing. Uses SRFI-158 generators for input creation and SRFI-194 for deterministic random sources. Provides built-in generators for all R7RS-small types.

**Key procedures**:
- `test-property` -- core macro, takes generators list and a predicate
- `test-property-expect-fail`, `test-property-skip`, `test-property-error`, `test-property-error-type` -- variants
- Rich generator set: `boolean-generator`, `char-generator`, `string-generator`, `symbol-generator`, `bytevector-generator`, `integer-generator`, `rational-generator`, `real-generator`, `complex-generator`, plus exact/inexact variants of each numeric type
- Composite: `list-generator-of`, `vector-generator-of`, `pair-generator-of`, `procedure-generator-of`

**Shrinking**: Not documented. No shrinking strategy is described in the specification.

**Implementations**:
- Chicken 5: Packaged as `srfi-252` egg (announced 2025-02-14 by Peter McGoron). Depends on srfi-194.
- Guile: **No known implementation exists.** SRFI-252 depends on SRFI-194 (which Guile does not ship natively), making a port nontrivial but feasible.

**Relationship to hegel-guile**: SRFI-252 is the "proper" portable Scheme approach -- local generation, SRFI-158 generator protocol, SRFI-64 integration. It lacks shrinking entirely. hegel-guile gets shrinking for free from Hypothesis. SRFI-252 is self-contained (no external process); hegel-guile requires hegel-core. They solve different problems: SRFI-252 aims for portability across Scheme implementations; hegel-guile aims for maximum PBT engine quality via Hypothesis.

---

#### 2.2 Racket quickcheck

- **URL**: https://docs.racket-lang.org/quickcheck/index.html
- **Package**: `quickcheck` (via `raco pkg install quickcheck`)
- **Scheme**: Racket (not portable Scheme)
- **Status**: Maintained. Works with Racket 6.0+, documented against Racket 9.1.
- **Authors**: Mike Sperber, Ismael Figueroa

**API style**: Close to Haskell QuickCheck. `property` form for defining specifications. `quickcheck` and `quickcheck-results` for execution. `config` struct for test parameters.

**Generators**: 20+ types via `choose-*` convention: `choose-integer`, `choose-real`, `choose-ascii-char`, `choose-list`, `choose-vector`, `choose-string`, `choose-symbol`, `choose-one-of`, `choose-mixed`, `choose-with-frequencies`. Pre-built `arbitrary-*` functions for common types. `bind-generators` for dependent generation.

**Shrinking**: Not documented in the available materials. Classical QuickCheck approach without integrated shrinking.

**RackUnit integration**: `rackunit/quickcheck` module provides `check-property` for use within RackUnit test suites.

---

#### 2.3 rackcheck

- **URL**: https://github.com/Bogdanp/rackcheck / https://docs.racket-lang.org/rackcheck/index.html
- **Scheme**: Racket
- **Version**: 2.0+ (rackcheck-lib)
- **Status**: Low activity (34 stars, last GitHub update 2026-01-11, but core work from 2020)
- **Author**: Bogdan Popa
- **License**: BSD-3-Clause

**API style**: Modern, built from scratch rather than porting QuickCheck. Uses `gen:` prefix for generators. `property` and `define-property` forms. `check-property` for execution.

**Key innovation**: **Integrated shrinking via shrink trees.** This is the critical differentiator from Racket quickcheck. Shrink trees are lazy data structures encoding multiple reduction strategies. The source of randomness that led to generation is shrunk, preserving generation invariants without requiring separate shrink functions.

**Generators**: `gen:natural`, `gen:integer`, `gen:real`, `gen:boolean`, `gen:char`, `gen:list`, `gen:vector`, `gen:string`, `gen:symbol`, `gen:hash`. Combinators: `gen:map`, `gen:bind`, `gen:filter`, `gen:choice`, `gen:sized`, `gen:resize`, `gen:scale`. Extensive Unicode support.

**Features**: Label classification for test distribution analysis, configurable seeds for reproducibility, `sample` for REPL exploration.

**Relationship to hegel-guile**: rackcheck represents the state of the art for Scheme-family local-generation PBT. Its integrated shrinking approach parallels Hypothesis's internal shrinking. However, it is Racket-only and implements its own engine -- meaning it must independently reimplement every optimization Hypothesis has accumulated. hegel-guile gets Hypothesis's shrinking, database, and search strategy for free.

---

#### 2.4 Chicken test-generative

- **URL**: https://wiki.call-cc.org/eggref/5/test-generative
- **Scheme**: Chicken 5
- **Status**: Available egg, maintenance status unclear
- **Author**: David Krentzlin
- **License**: GPL-3.0

**API style**: Integrates on top of Chicken's `test` egg, so you use familiar `test-assert` / `test-equal` macros inside a `test-generative` form. Binds generators to names, exercises code up to N iterations (default 100), stops on first failure and reports the seed.

**Generators**: Generators are plain thunks. The library itself provides no built-in generators -- it delegates to the `data-generators` egg for predefined types.

**Shrinking**: None.

**Relationship to hegel-guile**: test-generative is the simplest approach in the ecosystem -- just "run your existing tests N times with random inputs." No shrinking, no property combinators, no search intelligence. hegel-guile is categorically more powerful.

---

#### 2.5 Chicken data-generators

- **URL**: https://wiki.call-cc.org/eggref/4/data-generators (Chicken 4, outdated)
- **Scheme**: Chicken 4 (needs porting to Chicken 5)
- **Author**: David Krentzlin
- **Status**: Outdated (Chicken 4 only)

**Generators**: The most complete Scheme generator library I found. Primitives for fixnums (odd, even, various bit-widths: int8/16/32/64, uint8/16/32/64), reals, flonums, rationals, characters (from charsets or ranges), booleans, constants, procedures, series. Combinators: `gen-pair-of`, `gen-tuple-of`, `gen-list-of`, `gen-vector-of`, `gen-alist-of`, `gen-string-of`, `gen-symbol-of`, `gen-keyword-of`, `gen-hash-table-of`, `gen-record`, `gen-transform`, `gen-sample-of`. Size control via `with-size`.

**Relevance**: This library demonstrates what a rich local generator API looks like in Scheme. hegel-guile's generator module (`generators.scm`) produces JSON schemas sent to hegel-core, which is architecturally different -- the schema is a description of what to generate, not a thunk that generates.

---

#### 2.6 cluckcheck

- **URL**: https://github.com/mcandre/cluckcheck / https://wiki.call-cc.org/eggref/5/cluckcheck
- **Scheme**: Chicken 5
- **Version**: 0.0
- **Status**: Abandoned (13 stars, last meaningful update years ago)
- **Author**: Andrew Pennebaker
- **License**: BSD

**API style**: Minimal QuickCheck port. `for-all` tests a property with generated values. Generators: `gen-int`, `gen-bool`, `gen-char`, `gen-string`, `gen-list`.

**Shrinking**: None.

**Relationship to hegel-guile**: Toy-scale implementation. Five generators, no shrinking, no combinators, no search strategy.

---

### 3. NO KNOWN PBT IMPLEMENTATIONS

The following Scheme implementations have **no known PBT libraries**:

| Scheme | Notes |
|--------|-------|
| Chez Scheme | thunderchez provides utility libraries but no PBT. No QuickCheck port found. |
| Gambit Scheme | No PBT library found in any search. |
| MIT/GNU Scheme | No PBT library found. |
| Kawa Scheme | JVM-based; could theoretically use JUnit-QuickCheck, but no Scheme-native PBT. |
| Larceny | No PBT library found. |
| S7 Scheme | No PBT library found. |

---

### 4. GUIX'S OWN TESTING INFRASTRUCTURE

GNU Guix uses Guile extensively and has approximately 600 unit tests, all using SRFI-64 with a custom Automake test driver. System tests run full Guix System instances in VMs with lightweight instrumentation.

**PBT usage**: None found. Guix's test suite is entirely example-based (SRFI-64). Despite packaging guile-quickcheck, the Guix project itself does not appear to use property-based testing in its own codebase.

---

### 5. ACADEMIC RESEARCH

#### 5.1 Programmable Property-Based Testing (2026)

- **URL**: https://arxiv.org/abs/2602.18545
- **Authors**: Alperen Keles, Justine Frank, Ceren Mert, Harrison Goldstein, Leonidas Lampropoulos
- **Published**: February 2026

The most recent and relevant academic work. Introduces "deferred binding abstract syntax" to reify properties as data structures, decoupling property definition from testing execution. Implemented in both Rocq (dependent types) and **Racket** (dynamic types). Enables custom property runners without reimplementing frameworks.

**Relevance to hegel-guile**: This paper's insight -- that properties should be data structures separable from their runner -- is architecturally aligned with Hegel's design. Hegel separates the property (client-side Guile code) from the engine (hegel-core server). The paper provides theoretical grounding for why this separation is beneficial.

#### 5.2 Tuning Random Generators: PBT as Probabilistic Programming (2025)

- **URL**: https://arxiv.org/abs/2508.14394

Explores treating PBT generator tuning as a probabilistic programming problem. Relevant to understanding why delegating generation to a sophisticated engine (Hypothesis, via Hegel) is preferable to ad-hoc local generators.

---

### 6. THE HEGEL PROTOCOL (for context)

- **URL**: https://hegel.dev
- **Org**: https://github.com/hegeldev (hegel-core: 59 stars, hegel-rust: 156 stars)
- **Server**: hegel-core (Python, wraps Hypothesis)
- **Released clients**: hegel-rust
- **Announced/in-progress**: hegel-go, hegel-cpp, hegel-ocaml, hegel-typescript
- **Wire format**: Length-prefixed CBOR frames over Unix sockets
- **Philosophy**: PBT is a protocol problem, not a library problem

The protocol defines message types (handshake, start_test, draw, assume, finish_test_case, finish_test) where the client sends generator schemas as JSON-like structures (e.g., `{"type": "integers", "min_value": 100}`) and the server returns generated values. The server handles all generation, shrinking, and search strategy. The client is a thin adapter.

---

### 7. COMPARATIVE SUMMARY

| Library | Scheme | Generation | Shrinking | Engine Quality | Status |
|---------|--------|-----------|-----------|---------------|--------|
| **hegel-guile** | Guile 3 | Server (Hypothesis) | Server (Hypothesis) | Hypothesis-grade | Active |
| guile-quickcheck | Guile | Local | None | Minimal | Dormant |
| SRFI-252 | Portable (Chicken impl) | Local (SRFI-158) | None | Moderate | Final spec, early impl |
| rackcheck | Racket | Local | Integrated (shrink trees) | Good | Low activity |
| Racket quickcheck | Racket | Local | Undocumented | Moderate | Maintained |
| test-generative | Chicken 5 | Local (thunks) | None | Minimal | Available |
| cluckcheck | Chicken 5 | Local | None | Toy | Abandoned |
| data-generators | Chicken 4 | Local | N/A (generator only) | Good combinator set | Outdated |

---

### 8. KEY FINDINGS

**The Scheme PBT ecosystem is thin.** The only finalized standard is SRFI-252 (April 2024), which lacks shrinking and has exactly one implementation (Chicken). Guile's only native PBT library (guile-quickcheck) is a single-release project from 2021 with no shrinking and minimal generators. Racket is the only Scheme dialect with a genuinely capable PBT library (rackcheck), but it is Racket-specific and not portable.

**No Scheme PBT library implements shrinking well.** rackcheck has integrated shrinking via shrink trees, but all other Scheme PBT tools -- guile-quickcheck, SRFI-252, test-generative, cluckcheck -- lack shrinking entirely. This is the single largest gap in the ecosystem.

**hegel-guile's protocol-based approach is unique in the Scheme world.** No other Scheme PBT tool delegates generation to an external engine. Every existing approach implements generation locally. hegel-guile is the first to treat PBT as a protocol problem, inheriting Hypothesis's generation, shrinking, database, and search strategy without reimplementing any of it.

**SRFI-252 is the most interesting "competitor" for mindshare.** It is a finalized SRFI, builds on established SRFI infrastructure (SRFI-64, SRFI-158, SRFI-194), and could theoretically be implemented for Guile. However, it would still lack shrinking. A potential future where Guile has both SRFI-252 (for simple portable property tests) and hegel-guile (for Hypothesis-grade PBT) is coherent -- they serve different use cases, exactly as `define-hegel-test` complements SRFI-64 rather than replacing it.

---

### Sources

- [guile-quickcheck](https://ngyro.com/software/guile-quickcheck.html)
- [guile-quickcheck Guix package](https://guix.gnu.org/packages/guile-quickcheck-0.1.0/)
- [SRFI-252: Property Testing](https://srfi.schemers.org/srfi-252/)
- [SRFI-252 Chicken egg announcement](https://www.mail-archive.com/chicken-users@nongnu.org/msg21742.html)
- [SRFI-252 Chicken wiki](https://wiki.call-cc.org/eggref/5/srfi-252)
- [rackcheck (GitHub)](https://github.com/Bogdanp/rackcheck/)
- [rackcheck documentation](https://docs.racket-lang.org/rackcheck/index.html)
- [Racket quickcheck documentation](https://docs.racket-lang.org/quickcheck/index.html)
- [test-generative (Chicken)](https://wiki.call-cc.org/eggref/5/test-generative)
- [cluckcheck (GitHub)](https://github.com/mcandre/cluckcheck)
- [data-generators (Chicken 4)](https://wiki.call-cc.org/eggref/4/data-generators)
- [Guile Proba](https://luis-felipe.gitlab.io/guile-proba/)
- [Veritas (Codeberg)](https://codeberg.org/jjba23/veritas)
- [Hegel](https://hegel.dev)
- [How Hegel works](https://hegel.dev/explanation/how-hegel-works)
- [Hegel announcement (Antithesis blog)](https://antithesis.com/blog/2026/hegel/)
- [Hegel discussion (Lobsters)](https://lobste.rs/s/juc8ix/hegel_universal_property_based_testing)
- [hegel-core (GitHub)](https://github.com/hegeldev/hegel-core)
- [hegel-rust (GitHub)](https://github.com/hegeldev/hegel-rust)
- [Programmable Property-Based Testing (arXiv)](https://arxiv.org/abs/2602.18545)
- [Tuning Random Generators: PBT as Probabilistic Programming (arXiv)](https://arxiv.org/abs/2508.14394)
- [QuickCheck (Wikipedia)](https://en.wikipedia.org/wiki/QuickCheck)
- [SRFI-64: A Scheme API for test suites](https://srfi.schemers.org/srfi-64/)
- [SRFI-78: Lightweight testing](https://srfi.schemers.org/srfi-78/)
- [thunderchez (GitHub)](https://github.com/ovenpasta/thunderchez)