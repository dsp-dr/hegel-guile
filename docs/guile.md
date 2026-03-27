# hegel-guile API Reference

## Contents

1. [Module imports](#module-imports)
2. [Test definition](#test-definition)
3. [TestCase API](#testcase-api)
4. [Generators](#generators)
5. [Generator combinators](#generator-combinators)
6. [Composite generators](#composite-generators)
7. [Running tests](#running-tests)
8. [Error model](#error-model)
9. [Idiomatic patterns](#idiomatic-patterns)

---

## Module Imports

```scheme
;; Full public API
(use-modules (hegel))

;; Or individual sub-modules
(use-modules (hegel test)
             (hegel generators)
             (hegel test-case))
```

---

## Test Definition

### `define-hegel-test`

```scheme
(define-hegel-test (name tc)
  body ...)

(define-hegel-test (name tc #:test-cases n)
  body ...)
```

Defines and registers a property-based test. `tc` is the `TestCase` object
threaded through the body. Default `#:test-cases` is 100.

```scheme
;; 100 cases (default)
(define-hegel-test (test-addition-commutative tc)
  (let ((x (tc-draw tc (integers)))
        (y (tc-draw tc (integers))))
    (unless (= (+ x y) (+ y x))
      (error "not commutative" x y))))

;; 500 cases
(define-hegel-test (test-sort-idempotent tc #:test-cases 500)
  (let* ((xs   (tc-draw tc (lists-of (integers))))
         (once (sort xs <)))
    (unless (equal? once (sort once <))
      (error "sort not idempotent" xs))))
```

### `hegel-test` (inline/REPL)

```scheme
(hegel-test (tc)
  body ...)
```

Runs an anonymous test immediately with 100 cases. Useful in the REPL.

---

## TestCase API

### `tc-draw`

```scheme
(tc-draw tc schema)  →  value
```

Asks the Hegel server to draw a value matching `schema`. `schema` is a
generator (an alist produced by a generator function).

```scheme
(let ((n (tc-draw tc (integers #:min-value 0 #:max-value 100))))
  ...)
```

`tc-draw` handles client-side generator wrappers (`gen-filter`, `gen-map`)
transparently.

### `tc-assume`

```scheme
(tc-assume tc condition)
```

If `condition` is `#f`, marks the test case as invalid (filtered) and aborts
it — the server will not count it against the test-case budget. Equivalent to
Hypothesis's `assume()`.

```scheme
(let* ((a (tc-draw tc (integers)))
       (b (tc-draw tc (integers))))
  (tc-assume tc (not (= b 0)))
  (let ((result (quotient a b)))
    ...))
```

**Prefer direct generation over `tc-assume` when possible.** High rejection
rates (>10%) degrade test quality and slow shrinking.

---

## Generators

All generator functions return schema alists that `tc-draw` understands.
Keyword arguments follow Guile convention: `#:keyword value`.

### `(integers [#:min-value n] [#:max-value m])`

Generate integers. Guile integers are arbitrary precision — use unbounded by
default.

```scheme
(integers)                              ; any integer
(integers #:min-value 0)               ; non-negative
(integers #:min-value 1 #:max-value 6) ; dice roll
(integers #:max-value -1)              ; negative
```

### `(booleans)`

Generate `#t` or `#f`.

### `(floats [#:min-value x] [#:max-value y] [#:allow-nan b] [#:allow-infinity b])`

Generate IEEE 754 doubles.

```scheme
(floats)
(floats #:min-value 0.0 #:max-value 1.0)
(floats #:allow-nan #f #:allow-infinity #f)
```

### `(text [#:min-size n] [#:max-size m])`

Generate Unicode strings. Use without bounds for maximum bug-finding power —
Unicode edge cases (`ß` → `SS`, surrogates, combining chars) are where string
processing bugs hide.

```scheme
(text)
(text #:min-size 1)
(text #:max-size 20)
```

### `(binary [#:min-size n] [#:max-size m])`

Generate bytevectors (arbitrary binary data).

```scheme
(binary)
(binary #:min-size 1 #:max-size 64)
```

### `(lists-of element-schema [#:min-size n] [#:max-size m])`

Generate lists of values matching `element-schema`.

```scheme
(lists-of (integers))
(lists-of (text) #:min-size 1)
(lists-of (integers #:min-value 0 #:max-value 100) #:max-size 50)
```

**Large collections:** Draw size separately to get reliable large-collection
coverage and good shrinking:

```scheme
(let* ((n    (tc-draw tc (integers #:min-value 0 #:max-value 300)))
       (xs   (tc-draw tc (lists-of (integers) #:min-size n))))
  ...)
```

### `(one-of schema ...)`

Choose uniformly among the given schemas.

```scheme
(one-of (integers) (text) (booleans))
```

---

## Generator Combinators

### `(gen-filter schema pred)`

Client-side filter: only yield values satisfying `pred`. Internally calls
`tc-assume`, so high rejection rates are costly.

```scheme
;; Prefer this for high rejection:
(integers #:min-value 1)

;; gen-filter OK for low rejection:
(gen-filter (integers) odd?)
```

### `(gen-map schema proc)`

Transform drawn values with `proc`.

```scheme
;; Generate even integers
(gen-map (integers) (lambda (n) (* 2 n)))

;; Generate non-empty strings
(gen-map (lists-of (text #:min-size 1 #:max-size 10))
         (lambda (parts) (string-join parts " ")))
```

---

## Composite Generators

Use `define-composite` to build reusable generators that draw multiple values:

```scheme
(define-composite (rational-gen tc)
  (let* ((numer (tc-draw tc (integers)))
         (denom (tc-draw tc (integers #:min-value 1))))
    (/ numer denom)))

;; Use as a generator thunk:
(define-hegel-test (test-rational-add-commutative tc #:test-cases 200)
  (let ((a ((rational-gen) tc))
        (b ((rational-gen) tc)))
    (unless (= (+ a b) (+ b a))
      (error "rational addition not commutative" a b))))
```

---

## Running Tests

### `run-hegel-tests!`

```scheme
(run-hegel-tests!)  →  integer (number of failures)
```

Runs all tests registered with `define-hegel-test` in registration order.
Spawns `hegel-core`, runs all tests, closes the connection, returns failure count.

**Every test file must call `(run-hegel-tests!)` at the top level**, or the
registered tests will not execute.

Typical test file pattern:

```scheme
(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (hegel) (my-module))

(define-hegel-test (test-something tc) ...)
(define-hegel-test (test-something-else tc) ...)

(let ((failures (run-hegel-tests!)))
  (exit (if (= failures 0) 0 1)))
```

---

## Error Model

- **Test failure:** any uncaught exception thrown from the test body causes the
  case to be recorded as failed. Use `(error message args ...)` or any Guile
  `throw`.
- **`tc-assume` rejection:** throws the tag `'hegel-assume`; the runner marks
  the case `"invalid"` and the server does not count it.
- **Shrinking:** after a failure, `hegel-core` automatically shrinks the failing
  inputs and re-runs the test to find a minimal counterexample. The minimal
  inputs are reported by the server; the Guile runner prints them.

---

## Idiomatic Patterns

### Asserting no exception

```scheme
(define-hegel-test (test-parse-robust tc #:test-cases 1000)
  ;; my-parse should return #f or a value, never throw
  (let ((s (tc-draw tc (text))))
    (catch #t
      (lambda () (my-parse s))
      (lambda (tag . args)
        (error "parse threw an exception" s tag args)))))
```

### Model-based testing

```scheme
(define-hegel-test (test-queue-model tc #:test-cases 300)
  (let* ((ops  (tc-draw tc (lists-of (one-of (lists-of (integers) #:max-size 1)
                                             '())
                                     #:max-size 50)))
         (q    (make-queue))
         (ref  '()))
    (for-each (lambda (op)
                (if (null? op)
                    ;; dequeue
                    (unless (queue-empty? q)
                      (let ((v (dequeue! q))
                            (r (car ref)))
                        (set! ref (cdr ref))
                        (unless (equal? v r)
                          (error "dequeue mismatch" v r))))
                    ;; enqueue
                    (let ((x (car op)))
                      (enqueue! q x)
                      (set! ref (append ref (list x))))))
              ops)))
```

### Round-trip

```scheme
(define-hegel-test (test-json-roundtrip tc #:test-cases 500)
  (let* ((n   (tc-draw tc (integers)))
         (s   (my-json-encode n))
         (n2  (my-json-decode s)))
    (unless (equal? n n2)
      (error "round-trip failed" n s n2))))
```

### Dependent generation (avoid `tc-assume`)

```scheme
;; Draw a sorted pair without rejection sampling
(define-hegel-test (test-range-contains tc #:test-cases 200)
  (let* ((lo  (tc-draw tc (integers)))
         (hi  (tc-draw tc (integers #:min-value lo)))
         (x   (tc-draw tc (integers #:min-value lo #:max-value hi))))
    (unless (and (>= x lo) (<= x hi))
      (error "range violation" lo hi x))))
```
