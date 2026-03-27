;;; hegel/test-case.scm — TestCase record and generate/assume primitives
;;;
;;; Each test case operates on a channel. The server creates even-numbered
;;; channels for each test case (C-014). The client creates a muxed channel
;;; for the server-assigned channel-id and uses it for generate/mark_complete.

(define-module (hegel test-case)
  #:use-module (hegel protocol)
  #:use-module (hegel channel)
  #:use-module (hegel mux)
  #:use-module (srfi srfi-9)
  #:export (make-test-case
            make-test-case-on-mux
            test-case?
            test-case-channel
            tc-draw
            tc-assume))

;;;; ── Conditions ─────────────────────────────────────────────────────────────

(define %assume-tag 'hegel-assume)

(define (raise-assume!) (throw %assume-tag))

;;;; ── TestCase record ────────────────────────────────────────────────────────

(define-record-type <test-case>
  (%make-test-case channel)
  test-case?
  (channel test-case-channel))

(define (make-test-case channel)
  "Create a test case bound to an existing channel object."
  (%make-test-case channel))

(define (make-test-case-on-mux mux channel-id)
  "Create a test case for a server-assigned CHANNEL-ID via the connection MUX.
The server creates even-numbered channel IDs for each test case (C-014).
A muxed channel is created internally so generate/mark_complete traffic
on this channel is properly demultiplexed."
  (%make-test-case (make-muxed-channel channel-id mux)))

;;;; ── Generate (was: draw) ───────────────────────────────────────────────────

(define (tc-draw tc schema)
  "Ask the server to generate a value matching SCHEMA.
SCHEMA is an alist; e.g. '((\"type\" . \"integers\") (\"min_value\" . 0)).
Uses the 'generate' command on the test case's channel."
  (let* ((channel (test-case-channel tc))
         (resp (channel-send-request! channel (msg-generate schema))))
    (cond
     ((response-value resp)
      (response-value resp))
     ((response-error resp)
      (error "hegel server error during generate" (response-error resp)))
     (else
      ;; The result might be a plain value (integer, boolean, etc.)
      ;; channel-send-request! already unwraps the {"result": v} envelope,
      ;; so resp IS the value. Return it directly.
      resp))))

;;;; ── Assume ─────────────────────────────────────────────────────────────────

(define (tc-assume tc condition)
  "If CONDITION is false, send assume command and raise exception."
  (unless condition
    (channel-send-request! (test-case-channel tc) (msg-assume))
    (raise-assume!)))
