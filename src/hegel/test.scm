;;; hegel/test.scm — Test runner and define-hegel-test macro
;;;
;;; C-014: Server-driven test case lifecycle (hegel-core 0.2.3)
;;;
;;; Protocol flow:
;;;   1. Client sends run_test on control channel (ch 0)
;;;   2. Server acks with {"result": true}
;;;   3. Server sends {"event": "test_case", "channel_id": N} requests
;;;   4. Client acks each test_case, runs thunk, sends mark_complete
;;;   5. Server sends {"event": "test_done", "results": {...}} when finished
;;;
;;; The test runner is a tail-recursive event loop over the test channel.
;;; No explicit state machine — the recursion IS the state.

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
            run-single-test!
            execute-test-case!)
  #:re-export (tc-draw
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

;;;; ── Test case execution helper ──────────────────────────────────────────

(define (execute-test-case! mux event-msg thunk)
  "Execute THUNK for a single test case described by EVENT-MSG.
Creates a muxed channel for the server-assigned channel_id, runs THUNK
with generate/assume on that channel, sends mark_complete.
Returns the status string (VALID/INVALID/INTERESTING).

When the server sends a StopTest error (Hypothesis terminating the test
case internally), we absorb it and skip mark_complete — the server
already knows the test case is done."
  (let* ((test-case-channel-id (response-field event-msg "channel_id"))
         (tc (make-test-case-on-mux mux test-case-channel-id))
         (result (catch #t
                   (lambda ()
                     (thunk tc)
                     %status-valid)
                   (lambda (tag . args)
                     (if (eq? tag 'hegel-assume)
                         %status-invalid
                         %status-interesting)))))
    (let ((status result))
      ;; Send mark_complete; absorb StopTest error replies
      ;; (server sends StopTest as the reply when Hypothesis terminates
      ;; the test case — this is expected control flow, not a failure)
      (catch #t
        (lambda ()
          (channel-send-request! (test-case-channel tc)
                                 (msg-mark-complete status)))
        (lambda _ #f))
      status)))

;;;; ── Single test execution (C-014: server-driven event loop) ─────────────

(define (run-single-test! conn thunk test-cases)
  "Run THUNK against hegel-core using CONN. Returns #t if all cases passed.

The server drives the test case lifecycle:
  - Sends 'test_case' events with a channel_id for generate/assume
  - Sends 'test_done' event when Hypothesis is finished
The client loops over these events in tail position."
  (let* ((mux (hegel-connection-mux conn))
         (control (hegel-connection-control-channel conn))
         (test-channel-id (hegel-connection-next-test-channel-id! conn))
         (test-channel (make-muxed-channel test-channel-id mux)))
    ;; Send run_test on control channel; server acks with {"result": true}
    (channel-send-request! control (msg-run-test test-channel-id test-cases))
    ;; Tail-recursive event loop: read events on the test channel
    (let loop ((failures 0))
      (let* ((pkt (mux-read-for-channel! mux test-channel-id))
             (msg (cbor-decode (hegl-packet-payload pkt)))
             (event (response-event msg)))
        (cond
         ((equal? event "test_case")
          ;; Ack the test_case request from the server
          (channel-write-reply! test-channel
                                (hegl-packet-message-id pkt)
                                'null)
          ;; Execute thunk and report status
          (let ((status (execute-test-case! mux msg thunk)))
            (loop (if (string=? status %status-interesting)
                      (+ failures 1)
                      failures))))
         ((equal? event "test_done")
          ;; Ack the test_done event
          (channel-write-reply! test-channel
                                (hegl-packet-message-id pkt)
                                'null)
          ;; Return #t if no test cases were INTERESTING (failures)
          (= failures 0))
         (else
          (error "hegel: unexpected event in test loop" event msg)))))))

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
