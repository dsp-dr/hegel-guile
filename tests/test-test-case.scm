;;; tests/test-test-case.scm — Mock-based tests for hegel/test-case.scm
;;;
;;; The new test-case API uses channels (HEGL packets). To test offline,
;;; we create direct-mode channels backed by in-memory bytevector ports,
;;; pre-encoding HEGL packet replies that tc-draw/tc-assume will read.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel test-case)
             (hegel protocol)
             (hegel cbor)
             (hegel channel)
             (hegel packet)
             (srfi srfi-64)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports))

(test-begin "test-case")

;;;; ── Helper: create a reply packet as bytes ────────────────────────────────
;;
;; A channel-send-request! sends msg-id=1 on a channel, then expects a
;; reply packet with msg-id = (1 | reply-bit) containing {"result": val}.

(define (make-reply-packet-bytes channel-id msg-id value)
  "Encode a HEGL reply packet as a bytevector.
CHANNEL-ID and MSG-ID identify the packet.  VALUE is wrapped in {\"result\": val}."
  (call-with-values
    (lambda () (open-bytevector-output-port))
    (lambda (out get-bytes)
      (write-hegl-packet! out
        (make-hegl-packet channel-id
                          (logior msg-id %reply-bit)
                          (cbor-encode (list (cons "result" value)))))
      (get-bytes))))

(define (make-error-reply-packet-bytes channel-id msg-id error-msg error-type)
  "Encode a HEGL error reply packet as a bytevector."
  (call-with-values
    (lambda () (open-bytevector-output-port))
    (lambda (out get-bytes)
      (write-hegl-packet! out
        (make-hegl-packet channel-id
                          (logior msg-id %reply-bit)
                          (cbor-encode (list (cons "error" error-msg)
                                             (cons "type" error-type)))))
      (get-bytes))))

;;;; ── make-test-case creates a valid record ────────────────────────────────

(test-group "make-test-case"

  (let* ((mock-in  (open-bytevector-input-port (make-bytevector 0)))
         (mock-out (open-output-file "/dev/null"))
         (ch       (make-hegel-channel 3 mock-in mock-out))
         (tc       (make-test-case ch)))

    (test-assert "make-test-case returns a test-case record"
      (test-case? tc))

    (test-equal "test-case-channel accessor"
      ch
      (test-case-channel tc))))

;;;; ── tc-assume ────────────────────────────────────────────────────────────

(test-group "tc-assume with true condition"

  ;; tc-assume with #t is a no-op — doesn't send anything
  (let* ((mock-in  (open-bytevector-input-port (make-bytevector 0)))
         (mock-out (open-output-file "/dev/null"))
         (ch       (make-hegel-channel 3 mock-in mock-out))
         (tc       (make-test-case ch)))

    (test-assert "tc-assume with #t does not throw"
      (begin
        (tc-assume tc #t)
        #t))))

(test-group "tc-assume with false condition raises hegel-assume"

  ;; tc-assume with #f sends assume then raises.
  ;; The assume command goes through channel-send-request!, which expects
  ;; a reply packet.  Pre-encode that reply.
  (let* ((reply-bv (make-reply-packet-bytes 3 1 'null))
         (mock-in  (open-bytevector-input-port reply-bv))
         (mock-out (open-output-file "/dev/null"))
         (ch       (make-hegel-channel 3 mock-in mock-out))
         (tc       (make-test-case ch)))

    (test-assert "tc-assume with #f throws hegel-assume"
      (catch 'hegel-assume
        (lambda ()
          (tc-assume tc #f)
          #f)
        (lambda (key . args)
          (eq? key 'hegel-assume))))))

;;;; ── Exception tags ───────────────────────────────────────────────────────

(test-group "exception tags"

  (test-assert "raise-assume! throws hegel-assume"
    (catch 'hegel-assume
      (lambda ()
        ((@@ (hegel test-case) raise-assume!))
        #f)
      (lambda (key . args)
        (eq? key 'hegel-assume)))))

;;;; ── tc-draw with mock channel ──────────────────────────────────────────

(test-group "tc-draw with mocked HEGL reply"

  ;; tc-draw sends a generate request (msg-id 1), reads a reply with
  ;; msg-id = (1 | reply-bit) containing {"result": 42}
  (let* ((reply-bv (make-reply-packet-bytes 5 1 42))
         (mock-in  (open-bytevector-input-port reply-bv))
         (mock-out (open-output-file "/dev/null"))
         (ch       (make-hegel-channel 5 mock-in mock-out))
         (tc       (make-test-case ch)))

    (test-equal "tc-draw returns the generated value"
      42
      (tc-draw tc (list (cons "type" "integer")
                        (cons "min_value" 0)
                        (cons "max_value" 100)))))

  ;; tc-draw with string result
  (let* ((reply-bv (make-reply-packet-bytes 5 1 "hello"))
         (mock-in  (open-bytevector-input-port reply-bv))
         (mock-out (open-output-file "/dev/null"))
         (ch       (make-hegel-channel 5 mock-in mock-out))
         (tc       (make-test-case ch)))

    (test-equal "tc-draw returns string value"
      "hello"
      (tc-draw tc (list (cons "type" "string")))))

  ;; Verify tc-draw sends the correct generate command
  (call-with-values
    (lambda () (open-bytevector-output-port))
    (lambda (mock-out get-sent)
      (let* ((reply-bv (make-reply-packet-bytes 7 1 #t))
             (mock-in  (open-bytevector-input-port reply-bv))
             (ch       (make-hegel-channel 7 mock-in mock-out))
             (tc       (make-test-case ch))
             (_result  (tc-draw tc (list (cons "type" "boolean"))))
             ;; Decode what tc-draw sent
             (sent-raw (get-sent))
             (sent-in  (open-bytevector-input-port sent-raw))
             (sent-pkt (read-hegl-packet! sent-in))
             (sent-msg (cbor-decode (hegl-packet-payload sent-pkt))))

        (test-equal "tc-draw sends generate command"
          "generate" (response-command sent-msg))

        (let ((sent-schema (cdr (assoc "schema" sent-msg))))
          (test-equal "tc-draw sends the schema"
            "boolean" (cdr (assoc "type" sent-schema)))))))

  ;; tc-draw with an error reply should raise
  (let* ((err-bv  (make-error-reply-packet-bytes 5 1 "invalid schema" "InvalidArgument"))
         (mock-in (open-bytevector-input-port err-bv))
         (mock-out (open-output-file "/dev/null"))
         (ch       (make-hegel-channel 5 mock-in mock-out))
         (tc       (make-test-case ch)))

    (test-assert "tc-draw raises on error reply"
      (catch #t
        (lambda ()
          (tc-draw tc (list (cons "type" "integer")))
          #f)
        (lambda (key . args)
          #t)))))

(test-end "test-case")
