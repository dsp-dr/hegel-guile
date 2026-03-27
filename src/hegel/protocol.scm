;;; hegel/protocol.scm — Hegel wire protocol message constructors
;;;
;;; The actual hegel-core 0.2.2 protocol uses:
;;;   - "command" key (not "type") for client->server messages
;;;   - "run_test" (not "start_test"), "generate" (not "draw"),
;;;     "mark_complete" (not "finish_test_case")
;;;   - Handshake is raw bytes, not CBOR (handled in channel.scm)
;;;   - Server sends "event" messages, not "ok" responses

(define-module (hegel protocol)
  #:use-module (hegel cbor)
  #:use-module (rnrs bytevectors)
  #:export (;; Handshake constants
            %handshake-string
            %supported-protocol-versions
            parse-server-version
            ;; Status constants (match Python Status enum names)
            %status-valid
            %status-invalid
            %status-interesting
            ;; Command constructors (client -> server, CBOR payloads)
            msg-run-test
            msg-generate
            msg-assume
            msg-mark-complete
            ;; Response accessors
            response-field
            response-command
            response-event
            response-value
            response-error
            response-status
            response-channel-id
            response-is-final
            response-results))

;;;; ── Helpers ─────────────────────────────────────────────────────────────────

(define (alist . pairs) pairs)

;;;; ── Handshake ───────────────────────────────────────────────────────────────

(define %handshake-string
  (string->utf8 "hegel_handshake_start"))

(define %supported-protocol-versions '(0.6 . 0.7))  ; (min . max)

(define (parse-server-version payload-bv)
  "Parse server handshake reply bytevector (e.g. b\"Hegel/0.7\").
Returns the version as a number. Raises on invalid format or unsupported version."
  (let* ((str (utf8->string payload-bv))
         (prefix "Hegel/"))
    (unless (string-prefix? prefix str)
      (error "protocol: bad handshake response" str))
    (let ((version (string->number (substring str (string-length prefix)))))
      (unless version
        (error "protocol: bad version number" str))
      (unless (and (>= version (car %supported-protocol-versions))
                   (<= version (cdr %supported-protocol-versions)))
        (error "protocol: unsupported version" version
               %supported-protocol-versions))
      version)))

;;;; ── Status constants ───────────────────────────────────────────────────────
;;; hegel-core uses Python Status enum names (UPPERCASE, case-sensitive).
;;; The server does Status[message["status"]] — wrong case = KeyError.

(define %status-valid "VALID")
(define %status-invalid "INVALID")
(define %status-interesting "INTERESTING")

;;;; ── Command constructors ─────────────────────────────────────────────────────

(define (msg-run-test channel-id test-cases . opts)
  "Construct a run_test command.
CHANNEL-ID is the client-created test channel ID (integer).
TEST-CASES is the number of test cases to run (integer).
Optional keyword args: #:database, #:database-key, #:seed,
  #:suppress-health-check, #:derandomize.

Per hegel-core run_server_on_connection(), run_test must have channel_id
and test_cases at the top level (not nested in settings).  See conjecture C-12."
  (let loop ((opts opts)
             (extra '()))
    (cond
     ((null? opts)
      (append (list (cons "command" "run_test")
                    (cons "channel_id" channel-id)
                    (cons "test_cases" test-cases))
              (reverse extra)))
     ((eq? (car opts) #:database)
      (loop (cddr opts)
            (cons (cons "database" (cadr opts)) extra)))
     ((eq? (car opts) #:database-key)
      (loop (cddr opts)
            (cons (cons "database_key" (cadr opts)) extra)))
     ((eq? (car opts) #:seed)
      (loop (cddr opts)
            (cons (cons "seed" (cadr opts)) extra)))
     ((eq? (car opts) #:suppress-health-check)
      (loop (cddr opts)
            (cons (cons "suppress_health_check" (cadr opts)) extra)))
     ((eq? (car opts) #:derandomize)
      (loop (cddr opts)
            (cons (cons "derandomize" (cadr opts)) extra)))
     (else
      (error "msg-run-test: unknown keyword" (car opts))))))

(define (msg-generate schema)
  "Construct a generate command. SCHEMA is an alist."
  (alist (cons "command" "generate")
         (cons "schema" schema)))

(define (msg-assume)
  "Construct an assume command (mark test case as invalid)."
  (alist (cons "command" "assume")))

(define (msg-mark-complete status)
  "Construct a mark_complete command.
STATUS is a string: \"VALID\" | \"INVALID\" | \"INTERESTING\".
Must match Python Status enum names exactly (case-sensitive)."
  (alist (cons "command" "mark_complete")
         (cons "status" status)))

;;;; ── Response accessors ─────────────────────────────────────────────────────

(define (response-field msg key)
  (let ((pair (assoc key msg)))
    (and pair (cdr pair))))

(define (response-command msg)    (response-field msg "command"))
(define (response-event msg)     (response-field msg "event"))
(define (response-value msg)     (response-field msg "value"))
(define (response-error msg)     (response-field msg "error"))
(define (response-status msg)    (response-field msg "status"))
(define (response-channel-id msg)(response-field msg "channel_id"))
(define (response-is-final msg)  (response-field msg "is_final"))
(define (response-results msg)   (response-field msg "results"))
