;;; hegel/test.scm — Test runner and define-hegel-test macro
;;;
;;; Uses the actual hegel-core 0.2.2 protocol:
;;;   - "run_test" command on control channel (channel 0)
;;;   - Server sends "test_case" events for each test case
;;;   - Client uses "generate" (not "draw") and "mark_complete" (not "finish_test_case")
;;;   - Server decides when to stop (server-driven loop)

(define-module (hegel test)
  #:use-module (hegel server)
  #:use-module (hegel protocol)
  #:use-module (hegel channel)
  #:use-module (hegel test-case)
  #:use-module (hegel generators)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:export (define-hegel-test
            hegel-test
            run-hegel-tests!
            tc-draw
            tc-assume))

;;;; ── Test registry ─────────────────────────────────────────────────────────

(define *hegel-tests* '())

(define (register-test! name thunk test-cases)
  (set! *hegel-tests*
        (cons (list name thunk test-cases) *hegel-tests*)))

;;;; ── Macro API ─────────────────────────────────────────────────────────────

(define-syntax define-hegel-test
  (syntax-rules ()
    ((_ (name tc) body ...)
     (define-hegel-test (name tc #:test-cases 100) body ...))
    ((_ (name tc #:test-cases n) body ...)
     (begin
       (define (name tc) body ...)
       (register-test! 'name name n)))))

(define-syntax hegel-test
  (syntax-rules ()
    ((_ (tc) body ...)
     (let ((conn (make-hegel-connection)))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (run-single-test! conn (lambda (tc) body ...) 100))
         (lambda ()
           (close-hegel-connection! conn)))))))

;;;; ── Client-side generator resolution ──────────────────────────────────────

(define (effective-schema tc schema)
  "Resolve client-side generator wrappers (_filter, _map)."
  (let ((schema-type (cdr (assoc "type" schema))))
    (cond
     ((equal? schema-type "_filter")
      (let* ((inner (cdr (assoc "_schema" schema)))
             (pred  (cdr (assoc "_pred"  schema)))
             (val   (tc-draw tc inner)))
        (if (pred val)
            val
            (begin
              (tc-assume tc #f)
              val))))
     ((equal? schema-type "_map")
      (let* ((inner (cdr (assoc "_schema" schema)))
             (proc  (cdr (assoc "_proc"   schema))))
        (proc (tc-draw tc inner))))
     (else
      (tc-draw tc schema)))))

;;;; ── Single test execution ─────────────────────────────────────────────────

(define (run-single-test! conn thunk test-cases)
  "Run THUNK against hegel-core using CONN. Returns #t if all cases passed."
  (let* ((control (hegel-connection-control-channel conn))
         ;; Send run_test on control channel
         (resp (channel-send-request! control
                                      (msg-run-test #:test-cases test-cases))))
    ;; The server acknowledges with a response.
    ;; Now enter the test case loop: server-driven.
    ;; For the current protocol, we drive test cases from the client side,
    ;; iterating up to test-cases times. The server tells us when to stop
    ;; via the response to mark_complete.
    (let* ((test-channel (hegel-connection-next-test-channel! conn))
           (tc (make-test-case test-channel)))
      (let loop ((i 0) (failures 0))
        (if (= i test-cases)
            (= failures 0)
            (let ((result
                   (catch #t
                     (lambda ()
                       (thunk tc)
                       'valid)
                     (lambda (tag . args)
                       (cond
                        ((eq? tag 'hegel-assume) 'invalid)
                        (else 'interesting))))))
              ;; Report result to server
              (let ((mark-resp
                     (channel-send-request! test-channel
                                            (msg-mark-complete
                                             (symbol->string result)))))
                (loop (+ i 1)
                      (if (eq? result 'interesting)
                          (+ failures 1)
                          failures)))))))))

;;;; ── Run all registered tests ──────────────────────────────────────────────

(define (run-hegel-tests!)
  "Run all tests registered with define-hegel-test.
Returns number of failures."
  (let ((conn (make-hegel-connection))
        (failures 0))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (for-each
         (lambda (entry)
           (let ((name       (list-ref entry 0))
                 (thunk      (list-ref entry 1))
                 (test-cases (list-ref entry 2)))
             (format #t "~%Running ~a (~a cases)...~%" name test-cases)
             (let ((passed? (run-single-test! conn thunk test-cases)))
               (if passed?
                   (format #t "  ~a passed~%" name)
                   (begin
                     (set! failures (+ failures 1))
                     (format #t "  ~a FAILED~%" name))))))
         (reverse *hegel-tests*))
        failures)
      (lambda ()
        (close-hegel-connection! conn)))))
