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
  ;; run_test — C-12: channel_id and test_cases at top level, no settings nesting
  (let ((msg (msg-run-test 1 100)))
    (test-equal "run_test command key"
      "run_test" (response-command msg))
    (test-equal "run_test channel_id present"
      1 (response-field msg "channel_id"))
    (test-equal "run_test test_cases at top level"
      100 (response-field msg "test_cases"))
    (test-equal "run_test no settings key"
      #f (response-field msg "settings")))

  ;; run_test with different channel-id
  (let ((msg (msg-run-test 3 200)))
    (test-equal "run_test channel_id=3"
      3 (response-field msg "channel_id"))
    (test-equal "run_test test_cases=200"
      200 (response-field msg "test_cases")))

  ;; run_test with optional database
  (let ((msg (msg-run-test 1 50 #:database 'null)))
    (test-equal "run_test with database null"
      'null (response-field msg "database"))
    (test-equal "run_test with database still has channel_id"
      1 (response-field msg "channel_id")))

  ;; run_test with optional seed
  (let ((msg (msg-run-test 5 100 #:seed 42)))
    (test-equal "run_test with seed"
      42 (response-field msg "seed")))

  ;; run_test with optional database-key
  (let ((msg (msg-run-test 1 100 #:database-key 'null)))
    (test-equal "run_test with database_key"
      'null (response-field msg "database_key")))

  ;; run_test with optional derandomize
  (let ((msg (msg-run-test 1 100 #:derandomize #t)))
    (test-equal "run_test with derandomize"
      #t (response-field msg "derandomize")))

  ;; run_test with multiple optional fields
  (let ((msg (msg-run-test 7 500 #:database 'null #:seed 99 #:derandomize #f)))
    (test-equal "run_test multi-opt command"
      "run_test" (response-command msg))
    (test-equal "run_test multi-opt channel_id"
      7 (response-field msg "channel_id"))
    (test-equal "run_test multi-opt test_cases"
      500 (response-field msg "test_cases"))
    (test-equal "run_test multi-opt database"
      'null (response-field msg "database"))
    (test-equal "run_test multi-opt seed"
      99 (response-field msg "seed"))
    (test-equal "run_test multi-opt derandomize"
      #f (response-field msg "derandomize")))

  ;; generate
  (let* ((schema (list (cons "type" "integer")
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

  ;; mark_complete — status strings must be UPPERCASE (C-013)
  (let ((msg (msg-mark-complete %status-interesting)))
    (test-equal "mark_complete command"
      "mark_complete" (response-command msg))
    (test-equal "mark_complete status"
      "INTERESTING" (response-status msg)))

  (let ((msg (msg-mark-complete %status-valid)))
    (test-equal "mark_complete valid"
      "VALID" (response-status msg)))

  (let ((msg (msg-mark-complete %status-invalid)))
    (test-equal "mark_complete invalid"
      "INVALID" (response-status msg))))

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

  ;; run_test round-trip — C-12: flat structure with channel_id and test_cases
  (let* ((msg (msg-run-test 1 200))
         (decoded (cbor-decode (cbor-encode msg))))
    (test-equal "run_test round-trip command"
      "run_test" (cdr (assoc "command" decoded)))
    (test-equal "run_test round-trip channel_id"
      1 (cdr (assoc "channel_id" decoded)))
    (test-equal "run_test round-trip test_cases"
      200 (cdr (assoc "test_cases" decoded)))
    (test-equal "run_test round-trip no settings"
      #f (assoc "settings" decoded)))

  ;; run_test round-trip with optional fields
  (let* ((msg (msg-run-test 3 100 #:seed 42 #:database 'null))
         (decoded (cbor-decode (cbor-encode msg))))
    (test-equal "run_test round-trip seed"
      42 (cdr (assoc "seed" decoded)))
    (test-equal "run_test round-trip database"
      'null (cdr (assoc "database" decoded)))))

(test-end "protocol")
