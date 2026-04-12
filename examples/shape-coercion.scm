;;; examples/shape-coercion.scm — vector/list shape coercion property cage
;;;
;;; Origin: ported from guile-sage src/sage/util.scm:as-list
;;; (commit dsp-dr/guile-sage@15c7960, bd guile-p94).
;;;
;;; The pattern: in any Scheme codebase that crosses an FFI / JSON
;;; / serialisation boundary, JSON arrays may arrive as Scheme LISTS
;;; (because the parser builds them via cons) but get constructed
;;; outbound via list->vector. Downstream code that hard-codes one
;;; shape (vector?) silently breaks on the other (list?). The fix is
;;; a single defensive coercion helper at the boundary.
;;;
;;; sage hit this exact bug in ollama-parse-tool-call when llama3.2
;;; streamed tool_calls in the first chunk: the parser returned a
;;; list, the parser-tool-call hard-coded vector?, and tool calls
;;; vanished silently. The fix below is the same shape: as-list
;;; coerces vector | list | nil | #f to a canonical list, then
;;; downstream code only ever sees one shape.
;;;
;;; The properties below are the contract that any such helper must
;;; satisfy. Hegel's shrinker minimises any failure to the smallest
;;; counterexample, which is exactly what you want when debugging a
;;; coercion bug — the smallest input that breaks is usually the
;;; clearest signal.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel)
             (srfi srfi-1))

;;; The helper under test
(define (as-list obj)
  "Coerce vector / list / #f / '() to a canonical Scheme list.
   Throws on any other shape so type confusion is caught early."
  (cond
   ((not obj) '())
   ((null? obj) '())
   ((list? obj) obj)
   ((vector? obj) (vector->list obj))
   (else (error "as-list: cannot coerce" obj))))

;;; ── Property 1: as-list of a list is identity ─────────────────────────────
;;;
;;; (as-list lst) MUST equal lst when lst is already a proper list.
;;; This is the simplest case but pins the contract.

(define-hegel-test (test-as-list-list-identity tc #:test-cases 200)
  (let ((lst (tc-draw tc (lists-of (integers #:min-value 0 #:max-value 1000)
                                   #:max-size 30))))
    (unless (equal? (as-list lst) lst)
      (error "as-list of list must be identity" lst))))

;;; ── Property 2: as-list of vector preserves elements + cardinality ────────

(define-hegel-test (test-as-list-vector-roundtrip tc #:test-cases 200)
  (let* ((lst  (tc-draw tc (lists-of (integers #:min-value 0 #:max-value 1000)
                                     #:max-size 30)))
         (vec  (list->vector lst))
         (back (as-list vec)))
    (unless (and (list? back)
                 (= (length back) (vector-length vec))
                 (every equal? back lst))
      (error "as-list of vector must preserve elements" lst vec back))))

;;; ── Property 3: as-list of #f and nil produce empty list ──────────────────

(define-hegel-test (test-as-list-empty-cases tc #:test-cases 50)
  ;; Single trial case but exercised under the harness for uniformity.
  (let ((_ (tc-draw tc (integers #:min-value 0 #:max-value 1))))
    (unless (and (equal? (as-list #f) '())
                 (equal? (as-list '()) '()))
      (error "as-list of empty cases must be '()"))))

;;; ── Property 4: cardinality matches across all input shapes ───────────────
;;;
;;; The unifying invariant: for any supported input, (length (as-list x))
;;; equals the cardinality of the underlying container. If the helper
;;; ever drops or duplicates elements, this catches it.

(define-hegel-test (test-as-list-cardinality tc #:test-cases 300)
  (let* ((lst  (tc-draw tc (lists-of (integers #:min-value 0 #:max-value 1000)
                                     #:max-size 30)))
         ;; Randomly choose between list and vector representation
         (use-vec? (= 0 (modulo (tc-draw tc (integers #:min-value 0 #:max-value 1)) 2)))
         (input (if use-vec? (list->vector lst) lst))
         (expected (length lst)))
    (unless (= (length (as-list input)) expected)
      (error "as-list cardinality mismatch" input expected))))

;;; ── Run all ──────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
