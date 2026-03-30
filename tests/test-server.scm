;;; tests/test-server.scm — Mock-based tests for hegel/server.scm

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel server)
             (hegel mux)
             (hegel channel)
             (srfi srfi-64)
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
  ;; Record: (in-port out-port close-thunk control-channel mux server-version channel-counter)
  (let* ((mock-in  (open-input-file "/dev/null"))
         (mock-out (open-output-file "/dev/null"))
         (conn     ((@@ (hegel server) %make-hegel-connection)
                    mock-in mock-out (lambda () #f)
                    'mock-ctl 'mock-mux "0.7" 1)))

    (test-assert "hegel-connection? recognises the record"
      (hegel-connection? conn))

    (test-equal "hegel-connection-server-version returns version"
      "0.7"
      (hegel-connection-server-version conn))

    (test-equal "hegel-connection-mux returns stored mux"
      'mock-mux
      (hegel-connection-mux conn))

    (test-equal "hegel-connection-control-channel returns stored channel"
      'mock-ctl
      (hegel-connection-control-channel conn))

    (close-port mock-in)
    (close-port mock-out)))

;;;; ── close-hegel-connection! calls the close thunk ──────────────────────

(test-group "close-hegel-connection! invokes close-thunk"

  ;; close-hegel-connection! delegates to the transport-specific close-thunk.
  ;; Verify the thunk is called and ports are closed.
  (let* ((mock-in    (open-input-file "/dev/null"))
         (mock-out   (open-output-file "/dev/null"))
         (thunk-called? #f)
         (conn       ((@@ (hegel server) %make-hegel-connection)
                      mock-in mock-out
                      (lambda ()
                        (close-port mock-in)
                        (close-port mock-out)
                        (set! thunk-called? #t))
                      'mock-ctl 'mock-mux "0.7" 1)))
    (close-hegel-connection! conn)
    (test-assert "close-thunk was called"
      thunk-called?)
    (test-assert "in-port is closed after close"
      (port-closed? mock-in))
    (test-assert "out-port is closed after close"
      (port-closed? mock-out))))

;;;; ── make-hegel-connection (SKIPPED — requires live server) ───────────────
;;
;; make-hegel-connection spawns a real hegel-core process and connects
;; via Unix socket. It cannot be tested without a live server.
;; Integration tests for this function should be run separately.

(test-end "server")
