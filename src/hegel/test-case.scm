;;; hegel/test-case.scm — TestCase record and draw/assume primitives

(define-module (hegel test-case)
  #:use-module (hegel protocol)
  #:export (make-test-case
            tc-draw
            tc-assume
            test-case-failed?
            test-case-rejected?))

;;;; ── Conditions ─────────────────────────────────────────────────────────────

;; We use plain Guile exceptions (throw/catch) for control flow.
(define %assume-tag 'hegel-assume)
(define %fail-tag   'hegel-fail)

(define (raise-assume!) (throw %assume-tag))
(define (raise-fail! msg) (throw %fail-tag msg))

;;;; ── TestCase record ────────────────────────────────────────────────────────

(define-record-type <test-case>
  (%make-test-case in-port out-port)
  test-case?
  (in-port  test-case-in-port)
  (out-port test-case-out-port))

(define (make-test-case in-port out-port)
  (%make-test-case in-port out-port))

;;;; ── Draw ───────────────────────────────────────────────────────────────────

(define (tc-draw tc schema)
  "Ask the server to draw a value matching SCHEMA.
   SCHEMA is an alist; e.g. '((\"type\" . \"integers\") (\"min_value\" . 0))."
  (send-message! (test-case-out-port tc) (msg-draw schema))
  (let ((resp (recv-message! (test-case-in-port tc))))
    (cond
     ((equal? (response-type resp) "value")
      (response-value resp))
     ((equal? (response-type resp) "error")
      (error "hegel server error during draw" (response-error resp)))
     (else
      (error "hegel unexpected draw response" resp)))))

;;;; ── Assume ─────────────────────────────────────────────────────────────────

(define (tc-assume tc condition)
  "If CONDITION is false, mark this test case as invalid (filtered)."
  (unless condition
    (send-message! (test-case-out-port tc) (msg-assume))
    (raise-assume!)))
