;;; hegel/test.scm — Test runner and define-hegel-test macro

(define-module (hegel test)
  #:use-module (hegel server)
  #:use-module (hegel protocol)
  #:use-module (hegel test-case)
  #:use-module (hegel generators)
  #:use-module (srfi srfi-1)
  #:export (define-hegel-test
            hegel-test
            run-hegel-tests!
            ;; Re-export tc-draw/tc-assume for use in test bodies
            tc-draw
            tc-assume))

;;;; ── Test registry ───────────────────────────────────────────────────────────

(define *hegel-tests* '())

(define (register-test! name thunk test-cases)
  (set! *hegel-tests*
        (cons (list name thunk test-cases) *hegel-tests*)))

;;;; ── Macro API ───────────────────────────────────────────────────────────────

(define-syntax define-hegel-test
  (syntax-rules ()
    ((_ (name tc) body ...)
     (define-hegel-test (name tc #:test-cases 100) body ...))
    ((_ (name tc #:test-cases n) body ...)
     (begin
       (define (name tc) body ...)
       (register-test! 'name name n)))))

;; Inline (anonymous) test – useful in REPL exploration
(define-syntax hegel-test
  (syntax-rules ()
    ((_ (tc) body ...)
     (run-single-test! (lambda (tc) body ...) 100))))

;;;; ── Single test execution ───────────────────────────────────────────────────

(define (effective-schema tc schema)
  "Resolve client-side generator wrappers (_filter, _map)."
  (let ((type (cdr (assoc "type" schema))))
    (cond
     ((equal? type "_filter")
      (let* ((inner (cdr (assoc "_schema" schema)))
             (pred  (cdr (assoc "_pred"  schema)))
             (val   (tc-draw tc inner)))
        (if (pred val)
            val
            (begin
              (tc-assume tc #f)   ; raises assume exception
              val))))             ; unreachable
     ((equal? type "_map")
      (let* ((inner (cdr (assoc "_schema" schema)))
             (proc  (cdr (assoc "_proc"   schema))))
        (proc (tc-draw tc inner))))
     (else
      ;; Regular schema – send to server
      (tc-draw tc schema)))))

(define (run-single-test! conn thunk test-cases)
  "Run THUNK test-cases times using CONN. Return #t if passed."
  (let* ((port     (hegel-connection-port conn))
         (in-port  (car port))
         (out-port (cdr port)))
    ;; Tell server about the test
    (send-message! out-port (msg-start-test test-cases))
    (let ((resp (recv-message! in-port)))
      (unless (equal? (response-type resp) "ok")
        (error "hegel: start_test failed" resp)))
    ;; Run cases
    (let loop ((i 0) (failures 0))
      (if (= i test-cases)
          (begin
            (send-message! out-port (msg-finish-test "passed"))
            (recv-message! in-port)
            (= failures 0))
          (begin
            (send-message! out-port (msg-start-test-case))
            (recv-message! in-port)
            (let* ((tc (make-test-case in-port out-port))
                   (result
                    (catch #t
                      (lambda ()
                        (thunk tc)
                        'passed)
                      (lambda (tag . args)
                        (cond
                         ((eq? tag 'hegel-assume) 'invalid)
                         (else 'failed))))))
              (send-message! out-port
                             (msg-finish-test-case
                              (symbol->string result)))
              (recv-message! in-port)
              (loop (+ i 1)
                    (if (eq? result 'failed)
                        (+ failures 1)
                        failures))))))))

;;;; ── Run all registered tests ───────────────────────────────────────────────

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
                   (format #t "  ✓ ~a passed~%" name)
                   (begin
                     (set! failures (+ failures 1))
                     (format #t "  ✗ ~a FAILED~%" name))))))
         (reverse *hegel-tests*))
        failures)
      (lambda ()
        (close-hegel-connection! conn)))))
