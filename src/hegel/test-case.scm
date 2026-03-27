;;; hegel/test-case.scm — TestCase record and generate/assume primitives
;;;
;;; Each test case operates on a channel. The "generate" command replaces
;;; the old "draw" command, and "assume" marks a test case as invalid.

(define-module (hegel test-case)
  #:use-module (srfi srfi-9)
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
  (%make-test-case channel))

(define (make-test-case-on-mux mux channel-id)
  "Create a test case backed by a muxed channel for CHANNEL-ID.
Used in server-driven lifecycle (C-014): the server assigns the test_case
channel ID, and the client wraps it in a muxed channel for generate/assume."
  (%make-test-case (make-muxed-channel channel-id mux)))

;;;; ── Generate (was: draw) ───────────────────────────────────────────────────

(define (tc-draw tc schema)
  "Ask the server to generate a value matching SCHEMA.
SCHEMA is an alist; e.g. '((\"type\" . \"integer\") (\"min_value\" . 0)).
Uses the 'generate' command on the test case's channel.
channel-send-request! unwraps the {\"result\": v} envelope (C10),
so the return value is the bare generated value."
  (channel-send-request! (test-case-channel tc)
                         (msg-generate schema)))

;;;; ── Assume ─────────────────────────────────────────────────────────────────

(define (tc-assume tc condition)
  "If CONDITION is false, send assume command and raise exception."
  (unless condition
    (channel-send-request! (test-case-channel tc) (msg-assume))
    (raise-assume!)))
