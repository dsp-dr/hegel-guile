;;; tests/test-protocol.scm — Protocol message constructor tests
;;;
;;; Tests the actual hegel-core 0.2.2 command vocabulary:
;;;   run_test, generate, assume, mark_complete
;;; Handshake is raw bytes, not CBOR (tested in test-channel.scm).

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (hegel protocol)
             (hegel cbor)
             (rnrs bytevectors)
             (srfi srfi-64))

(test-begin "protocol")

;;;; ── Handshake ────────────────────────────────────────────────────────────────

(test-group "handshake"
  (test-equal "handshake string value"
    (string->utf8 "hegel_handshake_start")
    %handshake-string)

  (test-equal "handshake string length"
    21 (bytevector-length %handshake-string))

  ;; parse-server-version
  (test-equal "parse valid version"
    0.7 (parse-server-version (string->utf8 "Hegel/0.7")))

  (test-equal "parse version 0.6"
    0.6 (parse-server-version (string->utf8 "Hegel/0.6")))

  (test-error "reject bad prefix"
    #t (parse-server-version (string->utf8 "NotHegel/0.7")))

  (test-error "reject unsupported version"
    #t (parse-server-version (string->utf8 "Hegel/0.5")))

  (test-error "reject future version"
    #t (parse-server-version (string->utf8 "Hegel/1.0"))))

;;;; ── Command constructors ─────────────────────────────────────────────────────

(test-group "commands"
  ;; run_test
  (let ((msg (msg-run-test #:test-cases 100)))
    (test-equal "run_test command key"
      "run_test" (response-command msg))
    (let ((settings (response-field msg "settings")))
      (test-assert "has settings" settings)
      (test-equal "max_examples in settings"
        100 (cdr (assoc "max_examples" settings)))))

  ;; run_test with database null
  (let ((msg (msg-run-test #:test-cases 50 #:database 'null)))
    (test-equal "run_test with database"
      'null (response-field msg "database")))

  ;; generate
  (let* ((schema (list (cons "type" "integers")
                       (cons "min_value" 0)
                       (cons "max_value" 100)))
         (msg (msg-generate schema)))
    (test-equal "generate command"
      "generate" (response-command msg))
    (test-equal "generate schema"
      schema (response-field msg "schema")))

  ;; assume
  (let ((msg (msg-assume)))
    (test-equal "assume command"
      "assume" (response-command msg)))

  ;; mark_complete
  (let ((msg (msg-mark-complete "interesting")))
    (test-equal "mark_complete command"
      "mark_complete" (response-command msg))
    (test-equal "mark_complete status"
      "interesting" (response-status msg)))

  (let ((msg (msg-mark-complete "valid")))
    (test-equal "mark_complete valid"
      "valid" (response-status msg)))

  (let ((msg (msg-mark-complete "invalid")))
    (test-equal "mark_complete invalid"
      "invalid" (response-status msg))))

;;;; ── Response accessors ─────────────────────────────────────────────────────

(test-group "response-accessors"
  (let ((msg (list (cons "command" "generate")
                   (cons "value" 42))))
    (test-equal "response-command" "generate" (response-command msg))
    (test-equal "response-value" 42 (response-value msg)))

  (let ((msg (list (cons "event" "test_case")
                   (cons "status" "running"))))
    (test-equal "response-event" "test_case" (response-event msg))
    (test-equal "response-status" "running" (response-status msg)))

  (let ((msg (list (cons "error" "bad request"))))
    (test-equal "response-error" "bad request" (response-error msg)))

  ;; Missing keys return #f
  (let ((msg (list (cons "command" "ok"))))
    (test-equal "missing value" #f (response-value msg))
    (test-equal "missing error" #f (response-error msg))))

;;;; ── CBOR round-trip ──────────────────────────────────────────────────────────

(test-group "cbor-encoding"
  (let* ((msg (msg-generate (list (cons "type" "booleans"))))
         (encoded (cbor-encode msg))
         (decoded (cbor-decode encoded)))
    (test-equal "round-trip command"
      "generate" (cdr (assoc "command" decoded)))
    (test-equal "round-trip schema type"
      "booleans" (cdr (assoc "type"
                             (cdr (assoc "schema" decoded))))))

  ;; run_test round-trip
  (let* ((msg (msg-run-test #:test-cases 200))
         (decoded (cbor-decode (cbor-encode msg))))
    (test-equal "run_test round-trip command"
      "run_test" (cdr (assoc "command" decoded)))
    (test-equal "run_test round-trip max_examples"
      200 (cdr (assoc "max_examples"
                      (cdr (assoc "settings" decoded)))))))

(test-end "protocol")
