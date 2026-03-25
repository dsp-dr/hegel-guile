;;; tests/test-server.scm — Mock-based tests for hegel/server.scm

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel server)
             (srfi srfi-64)
             (ice-9 popen)
             (ice-9 binary-ports)
             (rnrs bytevectors)
             (rnrs io ports))

(test-begin "server")

;;;; ── find-hegel-command with HEGEL_SERVER_COMMAND env var ──────────────────

(test-group "find-hegel-command respects HEGEL_SERVER_COMMAND"

  ;; Save original value (if any) so we can restore it
  (let ((original (getenv "HEGEL_SERVER_COMMAND")))
    (dynamic-wind
      (lambda () (setenv "HEGEL_SERVER_COMMAND" "/usr/local/bin/my-hegel"))
      (lambda ()
        (test-equal "returns env var value when set"
          "/usr/local/bin/my-hegel"
          ((@@ (hegel server) find-hegel-command))))
      (lambda ()
        (if original
            (setenv "HEGEL_SERVER_COMMAND" original)
            (unsetenv "HEGEL_SERVER_COMMAND")))))

  ;; Also test with a different value to confirm it's not cached
  (let ((original (getenv "HEGEL_SERVER_COMMAND")))
    (dynamic-wind
      (lambda () (setenv "HEGEL_SERVER_COMMAND" "hegel --debug"))
      (lambda ()
        (test-equal "returns updated env var value"
          "hegel --debug"
          ((@@ (hegel server) find-hegel-command))))
      (lambda ()
        (if original
            (setenv "HEGEL_SERVER_COMMAND" original)
            (unsetenv "HEGEL_SERVER_COMMAND"))))))

;;;; ── Record type accessors ────────────────────────────────────────────────

(test-group "hegel-connection record accessors"

  ;; Construct a mock connection using the internal constructor.
  ;; We use placeholder values as stand-ins for the real port/proc objects.
  (let* ((mock-port (cons 'mock-in 'mock-out))
         (conn      ((@@ (hegel server) %make-hegel-connection)
                     mock-port 'mock-proc "1.2.3")))

    (test-assert "hegel-connection? recognises the record"
      ((@@ (hegel server) hegel-connection?) conn))

    (test-equal "hegel-connection-port returns the port pair"
      mock-port
      (hegel-connection-port conn))

    (test-equal "hegel-connection-proc returns the proc"
      'mock-proc
      ((@@ (hegel server) hegel-connection-proc) conn))

    (test-equal "hegel-connection-server-version returns version string"
      "1.2.3"
      ((@@ (hegel server) hegel-connection-server-version) conn))))

;;;; ── close-hegel-connection! ─────────────────────────────────────────────
;;
;; SKIPPED: close-hegel-connection! calls close-pipe on the subprocess,
;; which segfaults with mock pipes on FreeBSD/Guile 3.x. This function
;; is exercised by the live integration tests instead.

;;;; ── make-hegel-connection (SKIPPED — requires live server) ───────────────
;;
;; make-hegel-connection spawns a real hegel-core process and connects
;; via Unix socket. It cannot be tested without a live server.
;; Integration tests for this function should be run separately.

(test-end "server")
