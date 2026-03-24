;;; tests/test-protocol.scm — Protocol message & framing conjecture tests

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel cbor)
             (hegel protocol)
             (srfi srfi-64)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports))

(test-begin "protocol")

;;;; ── C-001: CBOR framing is length-prefixed uint32-BE ─────────────────────
;;
;; Conjecture: each frame is [4-byte BE uint32 length][CBOR payload].
;; We encode a known message, then verify the header matches payload size.

(test-group "C-001: length-prefixed uint32-BE framing"

  ;; Encode a simple message and inspect raw bytes
  (let ((msg (list (cons "type" "ok"))))
    (call-with-values
      (lambda () (open-bytevector-output-port))
      (lambda (out get-bytes)
        (cbor-encode-to-port out msg)
        (let* ((raw     (get-bytes))
               (raw-len (bytevector-length raw))
               ;; First 4 bytes should be the payload length in big-endian
               (header  (bytevector-u32-ref raw 0 (endianness big)))
               (payload-len (- raw-len 4)))
          (test-equal "header matches payload length"
            payload-len header)
          ;; Verify the payload itself decodes correctly
          (let* ((payload-bv (make-bytevector payload-len))
                 (_ (bytevector-copy! raw 4 payload-bv 0 payload-len))
                 (decoded (cbor-decode payload-bv)))
            (test-equal "payload decodes to original message"
              "ok" (cdr (assoc "type" decoded))))))))

  ;; Verify with a larger message (nested map)
  (let ((msg (list (cons "type" "start_test")
                   (cons "settings"
                         (list (cons "test_cases" 100))))))
    (call-with-values
      (lambda () (open-bytevector-output-port))
      (lambda (out get-bytes)
        (cbor-encode-to-port out msg)
        (let* ((raw     (get-bytes))
               (header  (bytevector-u32-ref raw 0 (endianness big)))
               (payload-len (- (bytevector-length raw) 4)))
          (test-equal "nested message: header matches payload"
            payload-len header)))))

  ;; Round-trip through port: encode then decode
  (let ((msg (list (cons "type" "draw")
                   (cons "schema"
                         (list (cons "type" "integers")
                               (cons "min_value" 0))))))
    (call-with-values
      (lambda () (open-bytevector-output-port))
      (lambda (out get-bytes)
        (cbor-encode-to-port out msg)
        (let* ((raw (get-bytes))
               (in  (open-bytevector-input-port raw))
               (decoded (cbor-decode-from-port in)))
          (test-equal "framed round-trip: type preserved"
            "draw" (response-type decoded))
          (let ((schema (cdr (assoc "schema" decoded))))
            (test-equal "framed round-trip: nested schema type"
              "integers" (cdr (assoc "type" schema)))))))))

;;;; ── C-002: Handshake is client-initiated ─────────────────────────────────
;;
;; Conjecture: client sends handshake first with type/client/version keys.
;; We verify the message structure is correct for client-initiated flow.

(test-group "C-002: handshake message structure"

  (let ((hs (msg-handshake "hegel-guile" "0.1.0")))
    (test-equal "handshake type" "handshake" (cdr (assoc "type" hs)))
    (test-equal "handshake client" "hegel-guile" (cdr (assoc "client" hs)))
    (test-equal "handshake version" "0.1.0" (cdr (assoc "version" hs)))
    ;; Exactly 3 keys
    (test-equal "handshake has 3 fields" 3 (length hs)))

  ;; Verify it survives CBOR round-trip
  (let* ((hs      (msg-handshake "hegel-guile" "0.1.0"))
         (encoded (cbor-encode hs))
         (decoded (cbor-decode encoded)))
    (test-equal "handshake CBOR round-trip: type"
      "handshake" (response-type decoded))
    (test-equal "handshake CBOR round-trip: client"
      "hegel-guile" (cdr (assoc "client" decoded)))
    (test-equal "handshake CBOR round-trip: version"
      "0.1.0" (cdr (assoc "version" decoded))))

  ;; Verify server response accessor works on a simulated response
  (let ((resp (list (cons "type" "handshake")
                    (cons "server_version" "0.2.2"))))
    (test-equal "response-server-version accessor"
      "0.2.2" (response-server-version resp))))

;;;; ── C-004: finish_test_case status strings ───────────────────────────────
;;
;; Conjecture: status is one of "passed", "failed", "invalid".
;; We verify each produces valid messages with the expected status field.

(test-group "C-004: finish_test_case status strings"

  ;; All three valid statuses
  (for-each
    (lambda (status)
      (let ((msg (msg-finish-test-case status)))
        (test-equal (string-append "finish_test_case type for " status)
          "finish_test_case" (cdr (assoc "type" msg)))
        (test-equal (string-append "finish_test_case status=" status)
          status (cdr (assoc "status" msg)))
        ;; CBOR round-trip
        (let ((decoded (cbor-decode (cbor-encode msg))))
          (test-equal (string-append "finish_test_case CBOR round-trip " status)
            status (cdr (assoc "status" decoded))))))
    '("passed" "failed" "invalid"))

  ;; finish_test has only "passed" and "failed"
  (for-each
    (lambda (status)
      (let ((msg (msg-finish-test status)))
        (test-equal (string-append "finish_test type for " status)
          "finish_test" (cdr (assoc "type" msg)))
        (test-equal (string-append "finish_test status=" status)
          status (cdr (assoc "status" msg)))))
    '("passed" "failed")))

;;;; ── Additional protocol message structure tests ──────────────────────────

(test-group "message constructors"

  (let ((msg (msg-start-test 200)))
    (test-equal "start_test type" "start_test" (cdr (assoc "type" msg)))
    (let ((settings (cdr (assoc "settings" msg))))
      (test-equal "start_test test_cases" 200 (cdr (assoc "test_cases" settings)))))

  (let ((msg (msg-start-test-case)))
    (test-equal "start_test_case type" "start_test_case" (cdr (assoc "type" msg)))
    (test-equal "start_test_case has 1 field" 1 (length msg)))

  (let ((msg (msg-draw (list (cons "type" "booleans")))))
    (test-equal "draw type" "draw" (cdr (assoc "type" msg)))
    (let ((schema (cdr (assoc "schema" msg))))
      (test-equal "draw schema type" "booleans" (cdr (assoc "type" schema)))))

  (let ((msg (msg-assume)))
    (test-equal "assume type" "assume" (cdr (assoc "type" msg)))
    (test-equal "assume has 1 field" 1 (length msg))))

;;;; ── Response accessors ───────────────────────────────────────────────────

(test-group "response accessors"

  (let ((msg (list (cons "type" "value") (cons "value" 42))))
    (test-equal "response-type" "value" (response-type msg))
    (test-equal "response-value" 42 (response-value msg)))

  (let ((msg (list (cons "type" "error") (cons "error" "bad request"))))
    (test-equal "response-error" "bad request" (response-error msg)))

  ;; Missing keys return #f
  (let ((msg (list (cons "type" "ok"))))
    (test-equal "missing value returns #f" #f (response-value msg))
    (test-equal "missing error returns #f" #f (response-error msg))))

(test-end "protocol")
