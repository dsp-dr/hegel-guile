;;; hegel/protocol.scm — Hegel wire protocol (CBOR over Unix socket)

(define-module (hegel protocol)
  #:use-module (hegel cbor)
  #:use-module (ice-9 binary-ports)
  #:export (;; Message constructors
            msg-handshake
            msg-start-test
            msg-start-test-case
            msg-draw
            msg-assume
            msg-finish-test-case
            msg-finish-test
            ;; Response accessors
            response-type
            response-value
            response-error
            response-server-version
            ;; Framed I/O
            send-message!
            recv-message!))

;;;; ── Helpers ─────────────────────────────────────────────────────────────────

(define (alist . pairs) pairs)

;;;; ── Message constructors ───────────────────────────────────────────────────

(define (msg-handshake client-name version)
  (alist (cons "type" "handshake")
         (cons "client" client-name)
         (cons "version" version)))

(define (msg-start-test test-cases)
  (alist (cons "type" "start_test")
         (cons "settings"
               (alist (cons "test_cases" test-cases)))))

(define (msg-start-test-case)
  (alist (cons "type" "start_test_case")))

(define (msg-draw schema)
  "SCHEMA is an alist like ((\"type\" . \"integers\") (\"min_value\" . 0))."
  (alist (cons "type" "draw")
         (cons "schema" schema)))

(define (msg-assume)
  "Sent when tc-assume fails; server marks the case as invalid."
  (alist (cons "type" "assume")))

(define (msg-finish-test-case status)
  "STATUS is a string: \"passed\" | \"failed\" | \"invalid\"."
  (alist (cons "type" "finish_test_case")
         (cons "status" status)))

(define (msg-finish-test status)
  "STATUS is a string: \"passed\" | \"failed\"."
  (alist (cons "type" "finish_test")
         (cons "status" status)))

;;;; ── Response accessors ─────────────────────────────────────────────────────

(define (response-field msg key)
  (let ((pair (assoc key msg)))
    (and pair (cdr pair))))

(define (response-type msg)  (response-field msg "type"))
(define (response-value msg) (response-field msg "value"))
(define (response-error msg) (response-field msg "error"))
(define (response-server-version msg) (response-field msg "server_version"))

;;;; ── Framed I/O ─────────────────────────────────────────────────────────────

(define (send-message! port msg)
  (cbor-encode-to-port port msg))

(define (recv-message! port)
  (cbor-decode-from-port port))
