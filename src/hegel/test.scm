;;; hegel/test.scm — Test runner and define-hegel-test macro
;;;
;;; Implements conjecture C-014: server-driven test case lifecycle.
;;;
;;; The hegel-core 0.2.3 protocol flow:
;;;   1. Client sends run_test on control channel (ch 0) with channel_id=N
;;;   2. Server replies {result: true} on control channel
;;;   3. Server sends {event: "test_case", channel_id: K} as REQUEST on ch N
;;;      (K is a server-created even channel for this specific test case)
;;;   4. Client replies {result: null} to acknowledge
;;;   5. Client sends generate commands on ch K
;;;   6. Client sends mark_complete on ch K
;;;   7. Server repeats 3-6 (Hypothesis decides how many)
;;;   8. Server sends {event: "test_done", results: {...}} on ch N
;;;   9. Client replies {result: null} to acknowledge

(define-module (hegel test)
  #:use-module (hegel server)
  #:use-module (hegel protocol)
  #:use-module (hegel channel)
  #:use-module (hegel mux)
  #:use-module (hegel packet)
  #:use-module (hegel cbor)
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

;;;; ── Single test case execution ────────────────────────────────────────────

(define (run-test-case! mux test-case-channel-id thunk)
  "Execute THUNK for a single test case on the server-created channel.
TEST-CASE-CHANNEL-ID is the even-numbered channel the server assigned.
Returns the status string sent to mark_complete."
  (let* ((tc (make-test-case-on-mux mux test-case-channel-id))
         (tc-channel (test-case-channel tc)))
    ;; Run the user's test function, catching exceptions
    (let ((status
           (catch #t
             (lambda ()
               (thunk tc)
               %status-valid)
             (lambda (tag . args)
               (cond
                ((eq? tag 'hegel-assume) %status-invalid)
                (else %status-interesting))))))
      ;; Report result to server on the test-case channel
      (channel-send-request! tc-channel (msg-mark-complete status))
      status)))

;;;; ── Server-driven event loop (C-014) ──────────────────────────────────────

(define (run-single-test! conn thunk test-cases)
  "Run THUNK against hegel-core using CONN. Returns #t if all cases passed.

The server drives test case iteration:
  - Sends 'test_case' events (requests) on the test channel
  - Client acknowledges each, runs thunk, sends mark_complete
  - Server sends 'test_done' when Hypothesis is done"
  (let* ((control (hegel-connection-control-channel conn))
         (mux     (hegel-connection-mux conn))
         ;; Allocate a client test channel ID for this test run
         (test-channel-id (hegel-connection-next-test-channel-id! conn))
         (test-channel    (make-muxed-channel test-channel-id mux)))
    ;; Send run_test on control channel (C-012: channel_id at top level)
    (channel-send-request! control
                           (msg-run-test test-channel-id
                                         test-cases))
    ;; Server-driven event loop: read requests on the test channel
    (let loop ((failures 0))
      (let* ((packet (mux-read-for-channel! mux test-channel-id))
             (payload (cbor-decode (hegl-packet-payload packet)))
             (event-type (response-event payload))
             (message-id (hegl-packet-message-id packet)))
        (cond
         ;; test_case event — server wants us to run a test case
         ((equal? event-type "test_case")
          (let ((tc-channel-id (response-field payload "channel_id")))
            ;; Acknowledge the test_case request (C-010: reply envelope)
            (channel-write-reply! test-channel message-id 'null)
            ;; Run the test case on the server-created channel
            (let ((status (run-test-case! mux tc-channel-id thunk)))
              (loop (if (string=? status %status-interesting)
                        (+ failures 1)
                        failures)))))

         ;; test_done event — Hypothesis has finished
         ((equal? event-type "test_done")
          ;; Acknowledge the test_done request
          (channel-write-reply! test-channel message-id 'null)
          (= failures 0))

         ;; Unexpected event — protocol violation
         (else
          (error "hegel: unexpected event on test channel"
                 event-type payload)))))))

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
