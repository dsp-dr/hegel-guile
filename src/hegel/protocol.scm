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
            response-status))

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

;;;; ── Command constructors ─────────────────────────────────────────────────────

(define (msg-run-test . opts)
  "Construct a run_test command. Keyword opts: #:test-cases, #:database."
  (let loop ((opts opts)
             (settings '())
             (extra '()))
    (cond
     ((null? opts)
      (let ((msg (alist (cons "command" "run_test"))))
        (if (null? settings)
            msg
            (append msg (list (cons "settings" (reverse settings)))
                    (reverse extra)))))
     ((eq? (car opts) #:test-cases)
      (loop (cddr opts)
            (cons (cons "max_examples" (cadr opts)) settings)
            extra))
     ((eq? (car opts) #:database)
      (loop (cddr opts)
            settings
            (cons (cons "database" (cadr opts)) extra)))
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
STATUS is a string: \"interesting\" | \"valid\" | \"invalid\"."
  (alist (cons "command" "mark_complete")
         (cons "status" status)))

;;;; ── Response accessors ─────────────────────────────────────────────────────

(define (response-field msg key)
  (let ((pair (assoc key msg)))
    (and pair (cdr pair))))

(define (response-command msg) (response-field msg "command"))
(define (response-event msg)   (response-field msg "event"))
(define (response-value msg)   (response-field msg "value"))
(define (response-error msg)   (response-field msg "error"))
(define (response-status msg)  (response-field msg "status"))
