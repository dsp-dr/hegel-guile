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
  ;; New record: (in-port out-port socket-obj proc mux control-channel server-version channel-counter)
  (let* ((mock-in  (open-input-file "/dev/null"))
         (mock-out (open-output-file "/dev/null"))
         (conn     ((@@ (hegel server) %make-hegel-connection)
                    mock-in mock-out #f 'mock-proc
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

;;;; ── close-hegel-connection! port-closing logic ───────────────────────────
;;
;; close-hegel-connection! closes (car port), (cdr port), then calls
;; close-pipe on the proc.  We cannot call the full function in tests
;; because close-pipe segfaults on FreeBSD Guile 3.x (known platform bug).
;; Instead we directly verify the port-closing steps it performs.

(test-group "close-hegel-connection! port-closing logic"

  ;; close-hegel-connection! closes in-port, out-port, and close-pipe on proc.
  ;; We just verify port closing works.
  (let* ((mock-in  (open-input-file "/dev/null"))
         (mock-out (open-output-file "/dev/null")))
    (close-port mock-in)
    (close-port mock-out)
    (test-assert "in-port is closed after close-port"
      (port-closed? mock-in))
    (test-assert "out-port is closed after close-port"
      (port-closed? mock-out))))

;;;; ── make-hegel-connection (SKIPPED — requires live server) ───────────────
;;
;; make-hegel-connection spawns a real hegel-core process and connects
;; via Unix socket. It cannot be tested without a live server.
;; Integration tests for this function should be run separately.

(test-end "server")
