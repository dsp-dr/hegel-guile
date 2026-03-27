;;; tests/test-channel.scm — Channel multiplexing tests

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (hegel channel)
             (hegel packet)
             (hegel cbor)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports)
             (srfi srfi-11)
             (srfi srfi-64))

(test-begin "channel")

;;;; ── Helpers ──────────────────────────────────────────────────────────────────

(define (make-pipe-pair)
  "Create a connected in/out port pair via bytevector ports.
For testing, we use a buffer: write to out, read from in."
  ;; We can't easily make a real pipe in pure Scheme tests,
  ;; so we test channel logic by writing packets to a buffer
  ;; and reading them back.
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (values out-port get-bv)))

;;;; ── Client channel ID encoding ───────────────────────────────────────────────

(test-group "channel-id-encoding"
  (test-equal "client channel 0 -> 1"
    1 (make-client-channel-id 0))
  (test-equal "client channel 1 -> 3"
    3 (make-client-channel-id 1))
  (test-equal "client channel 2 -> 5"
    5 (make-client-channel-id 2))
  ;; All client channels are odd
  (test-assert "client channels are odd"
    (odd? (make-client-channel-id 42))))

;;;; ── Message ID sequencing ────────────────────────────────────────────────────

(test-group "message-id-sequence"
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    ;; Create a channel with a dummy in-port (we only test sending)
    (let* ((dummy-in (open-bytevector-input-port (make-bytevector 0)))
           (channel (make-hegel-channel 0 dummy-in out-port)))
      ;; First three message IDs should be 1, 2, 3
      (test-equal "first msg-id" 1 (channel-next-message-id! channel))
      (test-equal "second msg-id" 2 (channel-next-message-id! channel))
      (test-equal "third msg-id" 3 (channel-next-message-id! channel)))))

;;;; ── Raw send/recv round-trip ─────────────────────────────────────────────────

(test-group "raw-round-trip"
  ;; Write a request packet, then construct a reply, and read it back
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((dummy-in (open-bytevector-input-port (make-bytevector 0)))
           (channel (make-hegel-channel 0 dummy-in out-port))
           (payload (string->utf8 "hegel_handshake_start"))
           (msg-id (channel-send-raw! channel payload)))
      (test-equal "send returns msg-id 1" 1 msg-id)
      ;; Verify the packet was written correctly
      (let* ((wire (get-bv))
             (pkt (read-hegl-packet! (open-bytevector-input-port wire))))
        (test-equal "packet channel-id" 0 (hegl-packet-channel-id pkt))
        (test-equal "packet message-id" 1 (hegl-packet-message-id pkt))
        (test-assert "not a reply" (not (hegl-packet-is-reply? pkt)))
        (test-equal "payload matches"
          payload (hegl-packet-payload pkt))))))

;;;; ── Reply validation ─────────────────────────────────────────────────────────

(test-group "reply-validation"
  ;; Construct a reply packet (msg-id 1 with reply bit set), read it
  (let-values (((reply-out get-reply) (open-bytevector-output-port)))
    (let ((reply-pkt (make-hegl-packet 0
                                        (logior 1 %reply-bit)
                                        (string->utf8 "Hegel/0.7"))))
      (write-hegl-packet! reply-out reply-pkt)
      (let* ((reply-bv (get-reply))
             (reply-in (open-bytevector-input-port reply-bv))
             (channel (make-hegel-channel 0 reply-in #f)))
        (let ((payload (channel-recv-raw! channel 1)))
          (test-equal "reply payload"
            (string->utf8 "Hegel/0.7") payload)))))

  ;; Wrong message ID should raise
  (let-values (((reply-out get-reply) (open-bytevector-output-port)))
    (let ((reply-pkt (make-hegl-packet 0
                                        (logior 5 %reply-bit)
                                        (string->utf8 "ok"))))
      (write-hegl-packet! reply-out reply-pkt)
      (let* ((reply-bv (get-reply))
             (reply-in (open-bytevector-input-port reply-bv))
             (channel (make-hegel-channel 0 reply-in #f)))
        (test-error "mismatched msg-id raises"
          #t
          (channel-recv-raw! channel 1))))))

;;;; ── CBOR send/recv ───────────────────────────────────────────────────────────

(test-group "cbor-round-trip"
  ;; Send a CBOR value, construct a CBOR reply, read it back
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((dummy-in (open-bytevector-input-port (make-bytevector 0)))
           (channel (make-hegel-channel 0 dummy-in out-port))
           (request-val (list (cons "command" "run_test")
                              (cons "test_cases" 100)))
           (msg-id (channel-send-cbor! channel request-val)))
      ;; Decode the written packet and verify CBOR payload
      (let* ((wire (get-bv))
             (pkt (read-hegl-packet! (open-bytevector-input-port wire)))
             (decoded (cbor-decode (hegl-packet-payload pkt))))
        (test-equal "cbor command key"
          "run_test" (cdr (assoc "command" decoded)))
        (test-equal "cbor test_cases"
          100 (cdr (assoc "test_cases" decoded)))))))

;;;; ── C-010: reply envelope {result: ...} / {error: ...} ─────────────────────

(test-group "c010-write-reply"
  ;; channel-write-reply! should produce a packet with reply bit set
  ;; and payload = CBOR-encoded {"result": value}
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((dummy-in (open-bytevector-input-port (make-bytevector 0)))
           (channel (make-hegel-channel 0 dummy-in out-port)))
      (channel-write-reply! channel 1 42)
      (let* ((wire (get-bv))
             (pkt (read-hegl-packet! (open-bytevector-input-port wire))))
        (test-assert "reply bit is set"
          (hegl-packet-is-reply? pkt))
        (test-equal "message-id has reply bit for msg 1"
          (logior 1 %reply-bit)
          (hegl-packet-message-id pkt))
        (let ((decoded (cbor-decode (hegl-packet-payload pkt))))
          (test-equal "payload is {\"result\": 42}"
            42 (cdr (assoc "result" decoded))))))))

(test-group "c010-write-reply-error"
  ;; channel-write-reply-error! should produce {error: msg, type: name}
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((dummy-in (open-bytevector-input-port (make-bytevector 0)))
           (channel (make-hegel-channel 0 dummy-in out-port)))
      (channel-write-reply-error! channel 3 "something broke" "ValueError")
      (let* ((wire (get-bv))
             (pkt (read-hegl-packet! (open-bytevector-input-port wire))))
        (test-assert "error reply bit is set"
          (hegl-packet-is-reply? pkt))
        (let ((decoded (cbor-decode (hegl-packet-payload pkt))))
          (test-equal "error message"
            "something broke" (cdr (assoc "error" decoded)))
          (test-equal "error type"
            "ValueError" (cdr (assoc "type" decoded))))))))

(test-group "c010-recv-unwrap-result"
  ;; channel-recv-cbor! should unwrap {"result": value} and return value
  (let-values (((reply-out get-reply) (open-bytevector-output-port)))
    (let ((reply-payload (cbor-encode (list (cons "result" "hello")))))
      (write-hegl-packet! reply-out
                          (make-hegl-packet 0
                                            (logior 1 %reply-bit)
                                            reply-payload))
      (let* ((reply-bv (get-reply))
             (reply-in (open-bytevector-input-port reply-bv))
             (channel (make-hegel-channel 0 reply-in #f)))
        (test-equal "unwraps result value"
          "hello"
          (channel-recv-cbor! channel 1))))))

(test-group "c010-recv-unwrap-result-alist"
  ;; When result is itself an alist, it should be returned as-is
  (let-values (((reply-out get-reply) (open-bytevector-output-port)))
    (let* ((inner-value (list (cons "event" "test_case") (cons "id" 7)))
           (reply-payload (cbor-encode (list (cons "result" inner-value)))))
      (write-hegl-packet! reply-out
                          (make-hegl-packet 0
                                            (logior 2 %reply-bit)
                                            reply-payload))
      (let* ((reply-bv (get-reply))
             (reply-in (open-bytevector-input-port reply-bv))
             (channel (make-hegel-channel 0 reply-in #f)))
        (let ((val (channel-recv-cbor! channel 2)))
          (test-equal "unwrapped alist event"
            "test_case" (cdr (assoc "event" val)))
          (test-equal "unwrapped alist id"
            7 (cdr (assoc "id" val))))))))

(test-group "c010-recv-error-raises"
  ;; channel-recv-cbor! should raise on {"error": msg, "type": name}
  (let-values (((reply-out get-reply) (open-bytevector-output-port)))
    (let ((reply-payload (cbor-encode (list (cons "error" "bad schema")
                                            (cons "type" "InvalidArgument")))))
      (write-hegl-packet! reply-out
                          (make-hegl-packet 0
                                            (logior 1 %reply-bit)
                                            reply-payload))
      (let* ((reply-bv (get-reply))
             (reply-in (open-bytevector-input-port reply-bv))
             (channel (make-hegel-channel 0 reply-in #f)))
        (test-error "error reply raises"
          #t
          (channel-recv-cbor! channel 1))))))

(test-group "c010-recv-bare-value-raises"
  ;; Bare CBOR value (not a map) should raise a C-010 violation
  (let-values (((reply-out get-reply) (open-bytevector-output-port)))
    (let ((reply-payload (cbor-encode 42)))
      (write-hegl-packet! reply-out
                          (make-hegl-packet 0
                                            (logior 1 %reply-bit)
                                            reply-payload))
      (let* ((reply-bv (get-reply))
             (reply-in (open-bytevector-input-port reply-bv))
             (channel (make-hegel-channel 0 reply-in #f)))
        (test-error "bare CBOR value raises C-010 violation"
          #t
          (channel-recv-cbor! channel 1))))))

(test-group "c010-send-request-unwraps"
  ;; channel-send-request! should round-trip through the envelope
  ;; We simulate: send request, then receive a {"result": ...} reply
  (let-values (((out-port get-sent) (open-bytevector-output-port)))
    (let-values (((reply-out get-reply) (open-bytevector-output-port)))
      ;; Pre-build the reply for msg-id 1
      (let ((reply-payload (cbor-encode (list (cons "result"
                                                    (list (cons "value" 999)))))))
        (write-hegl-packet! reply-out
                            (make-hegl-packet 0
                                              (logior 1 %reply-bit)
                                              reply-payload))
        (let* ((reply-bv (get-reply))
               (reply-in (open-bytevector-input-port reply-bv))
               (channel (make-hegel-channel 0 reply-in out-port)))
          (let ((result (channel-send-request! channel
                          (list (cons "command" "generate")
                                (cons "schema" (list (cons "type" "integers")))))))
            (test-equal "send-request unwraps result"
              999 (cdr (assoc "value" result)))))))))

(test-end "channel")
