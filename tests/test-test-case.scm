;;; tests/test-test-case.scm — Mock-based tests for hegel/test-case.scm

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel test-case)
             (hegel protocol)
             (hegel cbor)
             (srfi srfi-64)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports))

(test-begin "test-case")

;;;; ── Helper: discard-port ────────────────────────────────────────────────
;; A simple output port that discards writes (avoids bytevector-output-port issues).

(define (make-discard-port)
  (open-output-file "/dev/null"))

;;;; ── make-test-case creates a valid record ────────────────────────────────

(test-group "make-test-case"

  (let* ((mock-in  (open-bytevector-input-port (make-bytevector 0)))
         (mock-out (make-discard-port))
         (tc       (make-test-case mock-in mock-out)))

    (test-assert "make-test-case returns a test-case record"
      ((@@ (hegel test-case) test-case?) tc))

    (test-equal "test-case-in-port accessor"
      mock-in
      ((@@ (hegel test-case) test-case-in-port) tc))

    (test-equal "test-case-out-port accessor"
      mock-out
      ((@@ (hegel test-case) test-case-out-port) tc))))

;;;; ── tc-assume ────────────────────────────────────────────────────────────

(test-group "tc-assume with true condition"

  (let* ((mock-in  (open-bytevector-input-port (make-bytevector 0)))
         (mock-out (make-discard-port))
         (tc       (make-test-case mock-in mock-out)))

    (test-assert "tc-assume with #t does not throw"
      (begin
        (tc-assume tc #t)
        #t))))

(test-group "tc-assume with false condition raises hegel-assume"

  (let* ((mock-in  (open-bytevector-input-port (make-bytevector 0)))
         (mock-out (make-discard-port))
         (tc       (make-test-case mock-in mock-out)))

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
        (eq? key 'hegel-assume))))

  (test-assert "raise-fail! throws hegel-fail with message"
    (catch 'hegel-fail
      (lambda ()
        ((@@ (hegel test-case) raise-fail!) "test failure reason")
        #f)
      (lambda (key msg)
        (and (eq? key 'hegel-fail)
             (equal? msg "test failure reason"))))))

;;;; ── tc-draw with mock CBOR ports ─────────────────────────────────────────

(test-group "tc-draw with mocked CBOR response"

  ;; Build a mock server response: {"type": "value", "value": 42}
  ;; Encode as a length-prefixed CBOR frame, then feed to tc-draw.
  (call-with-values
    (lambda () (open-bytevector-output-port))
    (lambda (frame-out get-frame)
      (cbor-encode-to-port frame-out
                           (list (cons "type" "value") (cons "value" 42)))
      (let* ((response-bv (get-frame))
             (mock-in     (open-bytevector-input-port response-bv))
             (mock-out    (make-discard-port))
             (tc          (make-test-case mock-in mock-out)))
        (test-equal "tc-draw returns the drawn value"
          42
          (tc-draw tc (list (cons "type" "integers")
                            (cons "min_value" 0)
                            (cons "max_value" 100)))))))

  ;; Verify tc-draw sends the correct draw message
  (call-with-values
    (lambda () (open-bytevector-output-port))
    (lambda (frame-out get-frame)
      (cbor-encode-to-port frame-out
                           (list (cons "type" "value") (cons "value" "hello")))
      (let ((response-bv (get-frame)))
        (call-with-values
          (lambda () (open-bytevector-output-port))
          (lambda (mock-out get-sent)
            (let* ((mock-in  (open-bytevector-input-port response-bv))
                   (tc       (make-test-case mock-in mock-out))
                   (result   (tc-draw tc (list (cons "type" "booleans"))))
                   (sent-raw (get-sent))
                   (sent-in  (open-bytevector-input-port sent-raw))
                   (sent-msg (cbor-decode-from-port sent-in)))

              (test-equal "tc-draw returns string value"
                "hello" result)

              (test-equal "tc-draw sends a draw message"
                "draw" (response-type sent-msg))

              (let ((sent-schema (cdr (assoc "schema" sent-msg))))
                (test-equal "tc-draw sends the schema"
                  "booleans" (cdr (assoc "type" sent-schema))))))))))

  ;; tc-draw with an error response should raise
  (call-with-values
    (lambda () (open-bytevector-output-port))
    (lambda (frame-out get-frame)
      (cbor-encode-to-port frame-out
                           (list (cons "type" "error")
                                 (cons "error" "invalid schema")))
      (let* ((error-bv (get-frame))
             (mock-in  (open-bytevector-input-port error-bv))
             (mock-out (make-discard-port))
             (tc       (make-test-case mock-in mock-out)))
        (test-assert "tc-draw raises on error response"
          (catch #t
            (lambda ()
              (tc-draw tc (list (cons "type" "integers")))
              #f)
            (lambda (key . args)
              #t)))))))

(test-end "test-case")
