;;; examples/json-int-fuzz.scm — JSON int-arg shape fuzzing property cage
;;;
;;; Origin: ported from guile-sage src/sage/tools.scm:coerce->int
;;; (commit dsp-dr/guile-sage@769da88, bd guile-bcy).
;;;
;;; The pattern: LLM-emitted tool-call arguments are inconsistent
;;; about JSON int encoding. The same model can produce
;;;
;;;   "lines": 20         (JSON integer)
;;;   "lines": "20"       (JSON string of an integer)
;;;   "lines": 20.0       (JSON float that represents an integer)
;;;
;;; from one turn to the next. Any tool that does (min N other) or
;;; (take lst N) crashes when N is the wrong shape. The fix is a
;;; defensive coercion at the tool boundary.
;;;
;;; sage hit this in read_logs and search_logs: the wrong-type-arg
;;; crash propagated as a tool error and the model hallucinated fake
;;; 2023-era log lines to cover up the failure. Documented in
;;; docs/UX-FINDINGS-0.6.0.md gap N1.
;;;
;;; A subtle teaching moment lives inside this property: in Guile,
;;; (integer? 20.0) is #t — 20.0 IS mathematically an integer, just
;;; inexact. A naive coerce->int that fast-paths on integer? would
;;; return 20.0 unchanged and the downstream math STILL fails. The
;;; correct helper always runs through (inexact->exact (round ...))
;;; to guarantee exactness. The crash-freedom property catches the
;;; naive version on the first trial that draws a float.
;;;
;;; Hegel's shrinker is particularly valuable here because float
;;; counterexamples are unintuitive — you want the smallest float
;;; that triggers the bug, not whatever the LCG happened to draw.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel))

;;; The helper under test
(define (coerce->int v default)
  "Force a JSON-supplied value to a Scheme exact integer.
   #f / '()    -> default
   integer     -> exact integer
   float       -> rounded exact integer
   string      -> parsed via string->number, default if unparseable
   anything else -> default
   Important: always runs through (inexact->exact (round ...))
   because (integer? 20.0) is #t in Guile."
  (let ((raw (cond
              ((not v) default)
              ((null? v) default)
              ((number? v) v)
              ((string? v) (or (string->number v) default))
              (else default))))
    (if (number? raw)
        (inexact->exact (round raw))
        default)))

;;; ── Property 1: result is always an exact integer ─────────────────────────

(define-hegel-test (test-coerce-always-exact-int tc #:test-cases 500)
  (let* ((kind (modulo (tc-draw tc (integers #:min-value 0 #:max-value 6)) 7))
         (v (case kind
              ((0) (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
              ((1) (number->string (tc-draw tc (integers #:min-value -1000 #:max-value 1000))))
              ((2) (exact->inexact (tc-draw tc (integers #:min-value -1000 #:max-value 1000))))
              ((3) (string-append (number->string (tc-draw tc (integers #:min-value 0 #:max-value 1000)))
                                  ".5"))
              ((4) (tc-draw tc (text)))
              ((5) #f)
              ((6) '()))))
    (let ((result (coerce->int v 50)))
      (unless (and (number? result)
                   (exact? result)
                   (integer? result))
        (error "coerce->int must produce exact integer" v result)))))

;;; ── Property 2: function survives any input shape (no exception) ──────────

(define-hegel-test (test-coerce-never-throws tc #:test-cases 1000)
  (let* ((kind (modulo (tc-draw tc (integers #:min-value 0 #:max-value 6)) 7))
         (v (case kind
              ((0) (tc-draw tc (integers)))
              ((1) (number->string (tc-draw tc (integers #:min-value -10000 #:max-value 10000))))
              ((2) (exact->inexact (tc-draw tc (integers #:min-value -10000 #:max-value 10000))))
              ((3) (string-append (number->string (tc-draw tc (integers #:min-value 0 #:max-value 1000)))
                                  ".5"))
              ((4) (tc-draw tc (text)))
              ((5) #f)
              ((6) '()))))
    ;; Just calling it without a catch is the property — any exception
    ;; bubbles up as a hegel failure.
    (coerce->int v 50)))

;;; ── Property 3: integer input is preserved ────────────────────────────────

(define-hegel-test (test-coerce-integer-fixpoint tc #:test-cases 300)
  (let ((n (tc-draw tc (integers #:min-value -1000000 #:max-value 1000000))))
    (unless (= (coerce->int n 999) n)
      (error "exact integer must be a fixpoint" n))))

;;; ── Property 4: string-of-integer parses to the same integer ──────────────

(define-hegel-test (test-coerce-string-int-roundtrip tc #:test-cases 300)
  (let ((n (tc-draw tc (integers #:min-value -1000000 #:max-value 1000000))))
    (unless (= (coerce->int (number->string n) 999) n)
      (error "string-of-int must roundtrip" n))))

;;; ── Property 5: inexact integer (e.g. 20.0) becomes exact ─────────────────
;;;
;;; The (integer? 20.0) gotcha. A naive coerce->int that fast-paths
;;; on integer? would pass 20.0 through unchanged and downstream
;;; math would still fail.

(define-hegel-test (test-coerce-inexact-integer tc #:test-cases 300)
  (let* ((n (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (f (exact->inexact n))
         (result (coerce->int f 999)))
    (unless (and (exact? result)
                 (integer? result)
                 (= result n))
      (error "inexact integer must coerce to exact" n f result))))

;;; ── Property 6: garbage string falls back to default ──────────────────────

(define-hegel-test (test-coerce-garbage-default tc #:test-cases 100)
  ;; Generate strings that DEFINITELY won't parse as numbers (start
  ;; with a letter)
  (let* ((n (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (s (string-append "abc" (number->string n)))
         (default (tc-draw tc (integers #:min-value -1000 #:max-value 1000))))
    (unless (= (coerce->int s default) default)
      (error "garbage string must use default" s default))))

;;; ── Run all ──────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
