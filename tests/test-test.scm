;;; tests/test-test.scm — C14 server-driven test lifecycle state machine tests
;;;
;;; Simulates the hegel-core 0.2.3 protocol flow using bytevector pipes.
;;; Each test constructs the server-side packets the state machine expects
;;; and verifies the packets the client sends.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (hegel test)
             (hegel protocol)
             (hegel channel)
             (hegel mux)
             (hegel packet)
             (hegel cbor)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports)
             (srfi srfi-11)
             (srfi srfi-64))

(test-begin "test-runner")

;;;; ── Protocol accessor tests ─────────────────────────────────────────────

(let ((msg (list (cons "event" "test_case")
                 (cons "channel_id" 4)
                 (cons "is_final" #f))))
  (test-equal "response-channel-id"
    4 (response-channel-id msg))
  (test-equal "response-is-final"
    #f (response-is-final msg))
  (test-equal "response-event for test_case"
    "test_case" (response-event msg)))

(let ((msg (list (cons "event" "test_done")
                 (cons "results"
                       (list (cons "status" "passed")
                             (cons "count" 10))))))
  (test-equal "response-event for test_done"
    "test_done" (response-event msg))
  (test-assert "response-results is alist"
    (pair? (response-results msg)))
  (test-equal "results status"
    "passed" (cdr (assoc "status" (response-results msg)))))

;;;; ── execute-test-case! : valid thunk ────────────────────────────────────

(let* ((tc-channel-id 4)
       (generate-reply-payload
        (cbor-encode (list (cons "result" (list (cons "value" 42))))))
       (mark-reply-payload
        (cbor-encode (list (cons "result" 'null))))
       (generate-reply-pkt
        (make-hegl-packet tc-channel-id
                          (logior 1 %reply-bit)
                          generate-reply-payload))
       (mark-reply-pkt
        (make-hegl-packet tc-channel-id
                          (logior 2 %reply-bit)
                          mark-reply-payload)))
  (let-values (((wire-out get-wire) (open-bytevector-output-port)))
    (write-hegl-packet! wire-out generate-reply-pkt)
    (write-hegl-packet! wire-out mark-reply-pkt)
    (let* ((wire-bv (get-wire))
           (in-port (open-bytevector-input-port wire-bv)))
      (let-values (((out-port get-sent) (open-bytevector-output-port)))
        (let* ((mux (make-connection-mux in-port out-port))
               (event-msg (list (cons "event" "test_case")
                                (cons "channel_id" tc-channel-id)
                                (cons "is_final" #f)))
               (thunk (lambda (tc)
                        (tc-draw tc (list (cons "type" "integer")))))
               (result (execute-test-case! mux event-msg thunk)))
          (test-equal "execute-test-case valid returns VALID"
            "VALID" result))))))

;;;; ── execute-test-case! : failing thunk ──────────────────────────────────

(let* ((tc-channel-id 6)
       (mark-reply-payload
        (cbor-encode (list (cons "result" 'null))))
       (mark-reply-pkt
        (make-hegl-packet tc-channel-id
                          (logior 1 %reply-bit)
                          mark-reply-payload)))
  (let-values (((wire-out get-wire) (open-bytevector-output-port)))
    (write-hegl-packet! wire-out mark-reply-pkt)
    (let* ((wire-bv (get-wire))
           (in-port (open-bytevector-input-port wire-bv)))
      (let-values (((out-port get-sent) (open-bytevector-output-port)))
        (let* ((mux (make-connection-mux in-port out-port))
               (event-msg (list (cons "event" "test_case")
                                (cons "channel_id" tc-channel-id)
                                (cons "is_final" #f)))
               (thunk (lambda (tc)
                        (error "deliberate test failure")))
               (result (execute-test-case! mux event-msg thunk)))
          (test-equal "execute-test-case failing returns INTERESTING"
            "INTERESTING" result))))))

;;;; ── execute-test-case! : assume (invalid) ───────────────────────────────

(let* ((tc-channel-id 8)
       (assume-reply-payload
        (cbor-encode (list (cons "result" 'null))))
       (mark-reply-payload
        (cbor-encode (list (cons "result" 'null))))
       (assume-reply-pkt
        (make-hegl-packet tc-channel-id
                          (logior 1 %reply-bit)
                          assume-reply-payload))
       (mark-reply-pkt
        (make-hegl-packet tc-channel-id
                          (logior 2 %reply-bit)
                          mark-reply-payload)))
  (let-values (((wire-out get-wire) (open-bytevector-output-port)))
    (write-hegl-packet! wire-out assume-reply-pkt)
    (write-hegl-packet! wire-out mark-reply-pkt)
    (let* ((wire-bv (get-wire))
           (in-port (open-bytevector-input-port wire-bv)))
      (let-values (((out-port get-sent) (open-bytevector-output-port)))
        (let* ((mux (make-connection-mux in-port out-port))
               (event-msg (list (cons "event" "test_case")
                                (cons "channel_id" tc-channel-id)
                                (cons "is_final" #f)))
               (thunk (lambda (tc)
                        (tc-assume tc #f)))
               (result (execute-test-case! mux event-msg thunk)))
          (test-equal "execute-test-case assume returns INVALID"
            "INVALID" result))))))

;;;; ── msg-run-test with channel_id ────────────────────────────────────────

(let ((msg (msg-run-test 3 100)))
  (test-equal "run_test has channel_id"
    3 (response-channel-id msg))
  (test-equal "run_test has test_cases"
    100 (response-field msg "test_cases"))
  (test-equal "run_test command"
    "run_test" (response-command msg)))

(let* ((msg (msg-run-test 5 200))
       (decoded (cbor-decode (cbor-encode msg))))
  (test-equal "run_test round-trip channel_id"
    5 (cdr (assoc "channel_id" decoded))))

;;;; ── Full state machine: 2 test cases, all pass ─────────────────────────

(let* ((control-ch-id 0)
       (test-ch-id    1)
       (tc-ch-id-a    4)
       (tc-ch-id-b    6)

       ;; Control channel: reply to run_test
       (run-test-reply
        (make-hegl-packet control-ch-id
                          (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result" #t)))))

       ;; Test channel: test_case event for tc A
       (test-case-event-a
        (make-hegl-packet test-ch-id 10
                          (cbor-encode (list (cons "event" "test_case")
                                             (cons "channel_id" tc-ch-id-a)
                                             (cons "is_final" #f)))))
       ;; TC channel A: replies
       (tc-a-generate-reply
        (make-hegl-packet tc-ch-id-a (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result"
                                                   (list (cons "value" 42)))))))
       (tc-a-mark-reply
        (make-hegl-packet tc-ch-id-a (logior 2 %reply-bit)
                          (cbor-encode (list (cons "result" 'null)))))

       ;; Test channel: test_case event for tc B
       (test-case-event-b
        (make-hegl-packet test-ch-id 11
                          (cbor-encode (list (cons "event" "test_case")
                                             (cons "channel_id" tc-ch-id-b)
                                             (cons "is_final" #f)))))
       ;; TC channel B: replies
       (tc-b-generate-reply
        (make-hegl-packet tc-ch-id-b (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result"
                                                   (list (cons "value" 99)))))))
       (tc-b-mark-reply
        (make-hegl-packet tc-ch-id-b (logior 2 %reply-bit)
                          (cbor-encode (list (cons "result" 'null)))))

       ;; Test channel: test_done event
       (test-done-event
        (make-hegl-packet test-ch-id 12
                          (cbor-encode (list (cons "event" "test_done")
                                             (cons "results"
                                                   (list (cons "status" "passed")
                                                         (cons "count" 2))))))))

  (let-values (((wire-out get-wire) (open-bytevector-output-port)))
    (write-hegl-packet! wire-out run-test-reply)
    (write-hegl-packet! wire-out test-case-event-a)
    (write-hegl-packet! wire-out tc-a-generate-reply)
    (write-hegl-packet! wire-out tc-a-mark-reply)
    (write-hegl-packet! wire-out test-case-event-b)
    (write-hegl-packet! wire-out tc-b-generate-reply)
    (write-hegl-packet! wire-out tc-b-mark-reply)
    (write-hegl-packet! wire-out test-done-event)

    (let* ((wire-bv (get-wire))
           (in-port (open-bytevector-input-port wire-bv)))
      (let-values (((out-port get-sent) (open-bytevector-output-port)))
        (let* ((mux (make-connection-mux in-port out-port))
               (control (make-muxed-channel control-ch-id mux))
               (test-channel (make-muxed-channel test-ch-id mux))
               (thunk (lambda (tc)
                        (tc-draw tc (list (cons "type" "integer"))))))

          ;; 1. Send run_test on control channel
          (let ((resp (channel-send-request! control
                                             (msg-run-test test-ch-id 2))))
            (test-equal "run_test ack" #t resp))

          ;; 2. Event loop
          (let loop ((state 'waiting-for-event) (failures 0) (cases 0))
            (case state
              ((waiting-for-event)
               (let* ((pkt (mux-read-for-channel! mux test-ch-id))
                      (msg (cbor-decode (hegl-packet-payload pkt)))
                      (msg-id (hegl-packet-message-id pkt)))
                 (cond
                  ((equal? (response-event msg) "test_case")
                   (channel-write-reply! test-channel msg-id 'null)
                   (let ((result (execute-test-case! mux msg thunk)))
                     (loop 'waiting-for-event
                           (if (string=? result %status-interesting)
                               (+ failures 1) failures)
                           (+ cases 1))))
                  ((equal? (response-event msg) "test_done")
                   (channel-write-reply! test-channel msg-id 'null)
                   (loop 'done failures cases))
                  (else
                   (test-assert "unexpected event" #f)))))
              ((done)
               (test-equal "two test cases executed" 2 cases)
               (test-equal "zero failures" 0 failures)
               (test-assert "all passed" (= failures 0))))))))))

;;;; ── Full state machine: 1 pass, 1 fail ─────────────────────────────────

(let* ((control-ch-id 0)
       (test-ch-id    1)
       (tc-ch-id-a    4)
       (tc-ch-id-b    6)

       (run-test-reply
        (make-hegl-packet control-ch-id (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result" #t)))))

       ;; test_case A (will pass)
       (test-case-event-a
        (make-hegl-packet test-ch-id 10
                          (cbor-encode (list (cons "event" "test_case")
                                             (cons "channel_id" tc-ch-id-a)
                                             (cons "is_final" #f)))))
       (tc-a-generate-reply
        (make-hegl-packet tc-ch-id-a (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result"
                                                   (list (cons "value" 7)))))))
       (tc-a-mark-reply
        (make-hegl-packet tc-ch-id-a (logior 2 %reply-bit)
                          (cbor-encode (list (cons "result" 'null)))))

       ;; test_case B (will fail: thunk throws immediately, no generate)
       (test-case-event-b
        (make-hegl-packet test-ch-id 11
                          (cbor-encode (list (cons "event" "test_case")
                                             (cons "channel_id" tc-ch-id-b)
                                             (cons "is_final" #f)))))
       (tc-b-mark-reply
        (make-hegl-packet tc-ch-id-b (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result" 'null)))))

       ;; test_done
       (test-done-event
        (make-hegl-packet test-ch-id 12
                          (cbor-encode (list (cons "event" "test_done")
                                             (cons "results"
                                                   (list (cons "status" "failed"))))))))

  (let-values (((wire-out get-wire) (open-bytevector-output-port)))
    (write-hegl-packet! wire-out run-test-reply)
    (write-hegl-packet! wire-out test-case-event-a)
    (write-hegl-packet! wire-out tc-a-generate-reply)
    (write-hegl-packet! wire-out tc-a-mark-reply)
    (write-hegl-packet! wire-out test-case-event-b)
    (write-hegl-packet! wire-out tc-b-mark-reply)
    (write-hegl-packet! wire-out test-done-event)

    (let* ((wire-bv (get-wire))
           (in-port (open-bytevector-input-port wire-bv)))
      (let-values (((out-port get-sent) (open-bytevector-output-port)))
        (let* ((mux (make-connection-mux in-port out-port))
               (control (make-muxed-channel control-ch-id mux))
               (test-channel (make-muxed-channel test-ch-id mux))
               (call-count 0)
               (thunk (lambda (tc)
                        (set! call-count (+ call-count 1))
                        (if (= call-count 1)
                            (tc-draw tc (list (cons "type" "integer")))
                            (error "deliberate failure")))))

          ;; 1. Send run_test
          (channel-send-request! control (msg-run-test test-ch-id 2))

          ;; 2. Event loop
          (let loop ((state 'waiting-for-event) (failures 0) (cases 0))
            (case state
              ((waiting-for-event)
               (let* ((pkt (mux-read-for-channel! mux test-ch-id))
                      (msg (cbor-decode (hegl-packet-payload pkt)))
                      (msg-id (hegl-packet-message-id pkt)))
                 (cond
                  ((equal? (response-event msg) "test_case")
                   (channel-write-reply! test-channel msg-id 'null)
                   (let ((result (execute-test-case! mux msg thunk)))
                     (loop 'waiting-for-event
                           (if (string=? result %status-interesting)
                               (+ failures 1) failures)
                           (+ cases 1))))
                  ((equal? (response-event msg) "test_done")
                   (channel-write-reply! test-channel msg-id 'null)
                   (loop 'done failures cases))
                  (else
                   (test-assert "unexpected event" #f)))))
              ((done)
               (test-equal "failure: two test cases executed" 2 cases)
               (test-equal "failure: one failure" 1 failures)
               (test-assert "failure: not all passed" (not (= failures 0)))))))))))

;;;; ── Packet inspection: verify client sends correct packets ──────────────

(let* ((control-ch-id 0)
       (test-ch-id    1)
       (tc-ch-id-a    4)

       ;; Server packets
       (run-test-reply
        (make-hegl-packet control-ch-id (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result" #t)))))
       (test-case-event
        (make-hegl-packet test-ch-id 10
                          (cbor-encode (list (cons "event" "test_case")
                                             (cons "channel_id" tc-ch-id-a)
                                             (cons "is_final" #f)))))
       (tc-a-generate-reply
        (make-hegl-packet tc-ch-id-a (logior 1 %reply-bit)
                          (cbor-encode (list (cons "result"
                                                   (list (cons "value" 5)))))))
       (tc-a-mark-reply
        (make-hegl-packet tc-ch-id-a (logior 2 %reply-bit)
                          (cbor-encode (list (cons "result" 'null)))))
       (test-done-event
        (make-hegl-packet test-ch-id 11
                          (cbor-encode (list (cons "event" "test_done")
                                             (cons "results"
                                                   (list (cons "status" "passed"))))))))

  (let-values (((wire-out get-wire) (open-bytevector-output-port)))
    (write-hegl-packet! wire-out run-test-reply)
    (write-hegl-packet! wire-out test-case-event)
    (write-hegl-packet! wire-out tc-a-generate-reply)
    (write-hegl-packet! wire-out tc-a-mark-reply)
    (write-hegl-packet! wire-out test-done-event)

    (let* ((wire-bv (get-wire))
           (in-port (open-bytevector-input-port wire-bv)))
      (let-values (((out-port get-sent) (open-bytevector-output-port)))
        (let* ((mux (make-connection-mux in-port out-port))
               (control (make-muxed-channel control-ch-id mux))
               (test-channel (make-muxed-channel test-ch-id mux))
               (thunk (lambda (tc)
                        (tc-draw tc (list (cons "type" "integer"))))))

          ;; Execute the full flow
          (channel-send-request! control (msg-run-test test-ch-id 1))

          (let* ((pkt (mux-read-for-channel! mux test-ch-id))
                 (msg (cbor-decode (hegl-packet-payload pkt)))
                 (msg-id (hegl-packet-message-id pkt)))
            (channel-write-reply! test-channel msg-id 'null)
            (execute-test-case! mux msg thunk))

          (let* ((pkt (mux-read-for-channel! mux test-ch-id))
                 (msg (cbor-decode (hegl-packet-payload pkt)))
                 (msg-id (hegl-packet-message-id pkt)))
            (channel-write-reply! test-channel msg-id 'null))

          ;; Now inspect what the client sent
          (let ((sent-bv (get-sent)))
            (let ((sent-port (open-bytevector-input-port sent-bv)))

              ;; Packet 1: run_test request on channel 0
              (let* ((pkt1 (read-hegl-packet! sent-port))
                     (decoded1 (cbor-decode (hegl-packet-payload pkt1))))
                (test-equal "sent pkt1 channel" 0 (hegl-packet-channel-id pkt1))
                (test-assert "sent pkt1 is request"
                  (not (hegl-packet-is-reply? pkt1)))
                (test-equal "sent pkt1 command"
                  "run_test" (cdr (assoc "command" decoded1)))
                (test-equal "sent pkt1 channel_id"
                  test-ch-id (cdr (assoc "channel_id" decoded1)))
                (test-equal "sent pkt1 test_cases"
                  1 (cdr (assoc "test_cases" decoded1))))

              ;; Packet 2: reply to test_case event on test channel
              (let* ((pkt2 (read-hegl-packet! sent-port))
                     (decoded2 (cbor-decode (hegl-packet-payload pkt2))))
                (test-equal "sent pkt2 channel" test-ch-id
                  (hegl-packet-channel-id pkt2))
                (test-assert "sent pkt2 is reply"
                  (hegl-packet-is-reply? pkt2))
                (test-equal "sent pkt2 result is null"
                  'null (cdr (assoc "result" decoded2))))

              ;; Packet 3: generate request on tc channel 4
              (let* ((pkt3 (read-hegl-packet! sent-port))
                     (decoded3 (cbor-decode (hegl-packet-payload pkt3))))
                (test-equal "sent pkt3 channel" tc-ch-id-a
                  (hegl-packet-channel-id pkt3))
                (test-assert "sent pkt3 is request"
                  (not (hegl-packet-is-reply? pkt3)))
                (test-equal "sent pkt3 command"
                  "generate" (cdr (assoc "command" decoded3))))

              ;; Packet 4: mark_complete request on tc channel 4
              (let* ((pkt4 (read-hegl-packet! sent-port))
                     (decoded4 (cbor-decode (hegl-packet-payload pkt4))))
                (test-equal "sent pkt4 channel" tc-ch-id-a
                  (hegl-packet-channel-id pkt4))
                (test-assert "sent pkt4 is request"
                  (not (hegl-packet-is-reply? pkt4)))
                (test-equal "sent pkt4 command"
                  "mark_complete" (cdr (assoc "command" decoded4)))
                (test-equal "sent pkt4 status"
                  "VALID" (cdr (assoc "status" decoded4))))

              ;; Packet 5: reply to test_done on test channel
              (let* ((pkt5 (read-hegl-packet! sent-port))
                     (decoded5 (cbor-decode (hegl-packet-payload pkt5))))
                (test-equal "sent pkt5 channel" test-ch-id
                  (hegl-packet-channel-id pkt5))
                (test-assert "sent pkt5 is reply"
                  (hegl-packet-is-reply? pkt5))
                (test-equal "sent pkt5 result is null"
                  'null (cdr (assoc "result" decoded5)))))))))))

(test-end "test-runner")
