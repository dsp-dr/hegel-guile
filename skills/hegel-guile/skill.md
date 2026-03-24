---
name: hegel-guile
description: Write property-based tests using Hegel for GNU Guile 3. Triggers on: "property-based tests", "PBT", "hegel tests", "test with random inputs", "generative tests", "test properties", "randomized testing", "guile testing", "scheme property tests"
---

# Hegel for Guile: Property-Based Testing

Hegel is a universal property-based testing protocol powered by Hypothesis.
`hegel-guile` is the Guile 3 client: a thin layer that speaks the Hegel
CBOR-over-Unix-socket protocol to a `hegel-core` subprocess (Python/Hypothesis)
which handles data generation and shrinking.

Tests integrate with SRFI-64 and run via `guile -L src tests/my-test.scm`.

## Workflow

Follow these steps when writing property-based tests.

### 1. Detect Project and Load References

Identify hegel-guile presence from any of:

| Signal | Meaning |
|--------|---------|
| `*.org` containing `(hegel)` or `define-hegel-test` | Literate hegel-guile project |
| `src/hegel.scm` or `src/hegel/` | hegel-guile installed |
| `(use-modules (hegel))` in any `.scm` file | hegel-guile in use |

Load `references/guile.md` for API details and idiomatic patterns.

### 2. Explore the Code Under Test

Before writing any test, understand what you're testing:

- **Read the source** of the procedure/module under test
- **Read existing tests** to understand expected behavior and edge cases
- **Read docstrings and comments** for documented contracts
- **Read call sites** to see what callers expect

The goal is to find *evidence* for properties, not to invent them.

### 3. Identify Valuable Properties

Look for properties that are:

- **Grounded in evidence** from the code, docs, or usage patterns
- **Non-trivial** — they test real behavior, not tautologies
- **Falsifiable** — a buggy implementation could actually violate them

Write one test per property. Don't cram multiple properties into one test.

### 4. Check for Existing Tests to Evolve

Before writing from scratch, check existing tests:

- **Existing SRFI-64 `test-equal` / `test-assert` blocks** are prime candidates
  for evolution — especially parameterized ones, or suites that repeat a
  pattern with different inputs.
- **Tests with hardcoded representative values** often encode a general property
  that `define-hegel-test` can express directly.

When you evolve an existing test, **modify the existing test file** rather than
creating a new one. Add hegel tests alongside (or replacing) the existing tests
in the same `.scm` file. Do not create a separate `test-hegel.scm` — property
tests belong with the code they're testing.

### 5. Write the Tests

For each property:

1. **Add tests to the appropriate existing test file.** Only create a new file
   if no relevant test file exists.
2. Choose the **simplest possible generators** — start with no bounds, unless
   bounds are logically necessary.
3. Draw values with `(tc-draw tc schema)`.
4. Call the procedure under test.
5. Assert the property with `(unless ... (error ...))` or `(assert ...)`.

Minimal test skeleton:

```scheme
(use-modules (hegel))

(define-hegel-test (test-my-property tc #:test-cases 200)
  (let ((x (tc-draw tc (integers)))
        (y (tc-draw tc (integers))))
    (unless (= (+ x y) (+ y x))
      (error "commutativity violated" x y))))

(run-hegel-tests!)
```

### 6. Run and Reflect

```sh
guile -L src tests/my-test.scm
```

When a test fails, ask:

- **Is this a real bug?** Flag it to the user and ask what to do, or fix if
  instructed.
- **Is the property unsound?** If you asserted something the code never
  promised, fix the test.
- **Is the generator too broad?** Only add constraints if the failing input is
  genuinely outside the function's domain. Investigate before constraining.

---

## Property Categories

Use this taxonomy to identify what to test. Not every category applies to every
procedure — pick the ones supported by evidence.

| Category | Description | Guile example |
|----------|-------------|---------------|
| **Round-trip** | encode → decode recovers original | `(equal? x (string->number (number->string x)))` |
| **Idempotence** | applying twice equals once | `(equal? (sort xs <) (sort (sort xs <) <))` |
| **Commutativity** | order doesn't matter | `(= (+ x y) (+ y x))` |
| **Invariant preservation** | operation maintains structure | insert keeps list sorted |
| **Oracle / reference impl** | compare against known-correct impl | `(equal? (my-sort xs) (sort xs <))` |
| **Monotonicity** | more input → more output | `(>= (length (append a b)) (length a))` |
| **Bounds / contracts** | output within documented limits | `(and (>= r lo) (<= r hi))` |
| **No-crash / robustness** | handles all valid inputs | `(string->number arbitrary-string)` never throws |
| **Equivalence** | two implementations agree | iterative vs recursive |
| **Model-based** | matches a reference model | hash table ops match alist model |
| **Consistency** | related APIs agree | `string-length` matches char-by-char count |
| **Precision preservation** | values survive format conversions | `(= n (string->number (number->string n)))` |

---

## High-Value Patterns

### 1. Model Tests (Highest Value for Data Structures)

Compare your data structure against a known-good Guile standard type:

```scheme
(define-hegel-test (test-table-model tc #:test-cases 300)
  ;; Model: alist operations must agree with hash-table operations
  (let* ((keys   (tc-draw tc (lists-of (integers #:min-value 0 #:max-value 50)
                                       #:max-size 20)))
         (ht     (make-equal-hash-table))
         (model  '()))
    ;; Insert all keys
    (for-each (lambda (k)
                (hash-set! ht k (* k 2))
                (set! model (cons (cons k (* k 2))
                                  (alist-delete k model equal?))))
              keys)
    ;; Verify lookup agrees
    (for-each (lambda (k)
                (let ((ht-val    (hash-ref ht k #f))
                      (model-val (assoc k model)))
                  (unless (equal? ht-val (and model-val (cdr model-val)))
                    (error "model mismatch" k ht-val model-val))))
              keys)))
```

Choose oracle:
- `alist` for small maps
- `(make-equal-hash-table)` for hash maps under test
- `(sort xs <)` for ordered containers

### 2. Idempotence Tests (Highest Value for String/Text Processing)

```scheme
(define-hegel-test (test-string-normalize-idempotent tc #:test-cases 1000)
  (let* ((s    (tc-draw tc (text)))
         (once (my-normalize s))
         (twice (my-normalize once)))
    (unless (string=? once twice)
      (error "not idempotent" s once twice))))
```

Use `(text)` not `(text #:max-size 10)` — Unicode edge cases (`ß` → `SS`,
combining characters) are where bugs hide.

### 3. Parse Robustness (Universal — Test Every Parser)

```scheme
(define-hegel-test (test-parse-never-throws tc #:test-cases 500)
  (let ((s (tc-draw tc (text))))
    ;; Should return #f or a value, never throw
    (my-parse s)))
```

### 4. Round-Trip Tests

```scheme
(define-hegel-test (test-number-string-roundtrip tc #:test-cases 1000)
  (let* ((n  (tc-draw tc (integers #:min-value most-negative-fixnum
                                   #:max-value most-positive-fixnum)))
         (s  (number->string n))
         (n2 (string->number s)))
    (unless (= n n2)
      (error "round-trip failed" n s n2))))
```

### 5. Boundary Value Tests (Numeric Code)

Use `(integers)` with no bounds. Scheme integers are arbitrary precision, so
`most-positive-fixnum` / `most-negative-fixnum` are where C-FFI or
fixed-width arithmetic bugs appear. Don't add `.min-value -100 .max-value 100`
— those bounds hide real bugs.

---

## Generator Discipline

### Start With No Bounds

```scheme
;; GOOD
(tc-draw tc (integers))

;; BAD unless justified
(tc-draw tc (integers #:min-value 0 #:max-value 100))
```

### Edge Cases Are the Point

Don't narrow ranges to "avoid edge cases." Edge cases are what PBT is for.
If a procedure claims to work on all strings, test it on all strings —
including empty string, single-char, NUL bytes, surrogate-heavy Unicode.

### Don't Add `#:min-size 1` by Default

Unless the procedure's contract explicitly requires non-empty input, test with
`'()` too. A procedure that errors on empty input may be a bug worth knowing.

### When to Add Constraints

Add bounds **only** when:
1. The procedure's contract explicitly excludes some inputs.
2. You need to avoid undefined behavior (e.g., division by zero — use
   `(tc-assume tc (not (= y 0)))` or `(integers #:min-value 1)`).
3. A test failure has been investigated and confirmed out-of-domain.

### Prefer Generation Over Filtering

```scheme
;; GOOD — direct construction
(let* ((a (tc-draw tc (integers)))
       (b (tc-draw tc (integers #:min-value a))))
  ...)

;; OK for low rejection rates
(let* ((a (tc-draw tc (integers)))
       (b (tc-draw tc (integers))))
  (tc-assume tc (<= a b))
  ...)

;; BAD — ~50% rejection, defeats shrinking
(let* ((n (tc-draw tc (integers))))
  (tc-assume tc (even? n))
  ...)
;; GOOD instead:
(let* ((n (* 2 (tc-draw tc (integers)))))
  ...)
```

### Getting Large Collections

Hegel's default collection size is small. For large-collection bugs:

```scheme
;; GOOD — can generate large collections, shrinks well
(let* ((n    (tc-draw tc (integers #:min-value 0 #:max-value 300)))
       (keys (tc-draw tc (lists-of (integers) #:min-size n))))
  ...)
```

Set `#:min-size n` without `#:max-size` so Hegel can still go larger if needed,
but can shrink `n` to find the minimal collection that triggers the bug.

---

## Common Mistakes

1. **Over-constraining generators** — Adding `#:max-value 100` "just in case"
   hides real bugs.
2. **Testing trivial properties** — `(= x x)` is not a test. Every property
   must be falsifiable by a buggy implementation.
3. **Using the implementation as the oracle** — If your test calls the same
   procedure to compute expected output, it can never fail. Use an independent
   reference.
4. **High-rejection `tc-assume`** — If more than ~10% of cases are rejected,
   restructure the generators.
5. **Separate hegel test file** — Don't create `test-hegel.scm`. Add hegel
   tests to the existing test file for that module.
6. **Forgetting `(run-hegel-tests!)`** — The test file must call this at the
   end, or `guile` will exit without running anything.
7. **Not handling errors as test failures** — In Guile, use `(catch #t thunk
   handler)` if you want to assert a procedure *doesn't* throw; or let the
   natural throw propagate to signal failure.

---

## Quick Setup

### In a literate org-mode project (preferred)

Add a test section to your `.org` file:

```org
* Tests
:PROPERTIES:
:header-args:scheme: :tangle tests/test-my-module.scm :mkdirp t
:END:

#+begin_src scheme
(add-to-load-path "../src")
(use-modules (hegel) (my-module))

(define-hegel-test (test-my-property tc #:test-cases 200)
  ...)

(run-hegel-tests!)
#+end_src
```

Then tangle and run:

```sh
# Tangle
emacs --batch --eval "(progn (require 'ob-tangle) \
  (org-babel-tangle-file \"my-project.org\"))"

# Run
guile -L src tests/test-my-module.scm
```

### Standalone `.scm`

```scheme
(add-to-load-path "path/to/hegel-guile/src")
(use-modules (hegel))
```

Requires `hegel-core` reachable as `hegel` on PATH, or set:

```sh
export HEGEL_SERVER_COMMAND=/path/to/hegel-venv/bin/hegel
```

Install hegel-core:

```sh
uv tool install hegel-core
# or
pip install hegel-core
```

Run:

```sh
guile -L src tests/test-my-module.scm
```
