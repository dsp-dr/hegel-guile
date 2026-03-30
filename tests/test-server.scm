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

;;;; ── Transport selection (feature flag UATs) ────────────────────────────
;;
;; The transport config layer must:
;;   1. Default to stdio when HEGEL_TRANSPORT is unset
;;   2. Respect "stdio" and "socket" env var values
;;   3. Reject unknown transport values
;;   4. Accept #:transport keyword on make-hegel-connection (tested via
;;      the internal hegel-transport function; full make-hegel-connection
;;      requires a live server)

(define hegel-transport (@@ (hegel server) hegel-transport))

(test-group "transport selection: env var defaults"

  ;; Unset → default to stdio
  (let ((original (getenv "HEGEL_TRANSPORT")))
    (dynamic-wind
      (lambda () (unsetenv "HEGEL_TRANSPORT"))
      (lambda ()
        (test-equal "default transport is stdio when env unset"
          'stdio (hegel-transport)))
      (lambda ()
        (if original
            (setenv "HEGEL_TRANSPORT" original)
            (unsetenv "HEGEL_TRANSPORT"))))))

(test-group "transport selection: explicit stdio"

  (let ((original (getenv "HEGEL_TRANSPORT")))
    (dynamic-wind
      (lambda () (setenv "HEGEL_TRANSPORT" "stdio"))
      (lambda ()
        (test-equal "HEGEL_TRANSPORT=stdio returns stdio"
          'stdio (hegel-transport)))
      (lambda ()
        (if original
            (setenv "HEGEL_TRANSPORT" original)
            (unsetenv "HEGEL_TRANSPORT"))))))

(test-group "transport selection: explicit socket"

  (let ((original (getenv "HEGEL_TRANSPORT")))
    (dynamic-wind
      (lambda () (setenv "HEGEL_TRANSPORT" "socket"))
      (lambda ()
        (test-equal "HEGEL_TRANSPORT=socket returns socket"
          'socket (hegel-transport)))
      (lambda ()
        (if original
            (setenv "HEGEL_TRANSPORT" original)
            (unsetenv "HEGEL_TRANSPORT"))))))

(test-group "transport selection: reject invalid"

  (let ((original (getenv "HEGEL_TRANSPORT")))
    (dynamic-wind
      (lambda () (setenv "HEGEL_TRANSPORT" "tcp"))
      (lambda ()
        (test-assert "HEGEL_TRANSPORT=tcp raises error"
          (catch #t
            (lambda ()
              (hegel-transport)
              #f)
            (lambda (key . args)
              #t))))
      (lambda ()
        (if original
            (setenv "HEGEL_TRANSPORT" original)
            (unsetenv "HEGEL_TRANSPORT"))))))

(test-group "transport selection: empty string defaults to error"

  (let ((original (getenv "HEGEL_TRANSPORT")))
    (dynamic-wind
      (lambda () (setenv "HEGEL_TRANSPORT" ""))
      (lambda ()
        (test-assert "HEGEL_TRANSPORT='' raises error"
          (catch #t
            (lambda ()
              (hegel-transport)
              #f)
            (lambda (key . args)
              #t))))
      (lambda ()
        (if original
            (setenv "HEGEL_TRANSPORT" original)
            (unsetenv "HEGEL_TRANSPORT"))))))

(test-group "transport selection: case sensitive"

  ;; "STDIO" should be rejected — only lowercase is accepted
  (let ((original (getenv "HEGEL_TRANSPORT")))
    (dynamic-wind
      (lambda () (setenv "HEGEL_TRANSPORT" "STDIO"))
      (lambda ()
        (test-assert "HEGEL_TRANSPORT=STDIO is rejected (case sensitive)"
          (catch #t
            (lambda ()
              (hegel-transport)
              #f)
            (lambda (key . args)
              #t))))
      (lambda ()
        (if original
            (setenv "HEGEL_TRANSPORT" original)
            (unsetenv "HEGEL_TRANSPORT"))))))

;;;; ── finalize-connection is transport-agnostic ─────────────────────────
;;
;; finalize-connection takes in-port, out-port, close-thunk and performs
;; handshake + mux creation. We can't test it fully without a server,
;; but we verify the close-thunk is stored correctly in both transports.

(test-group "close-thunk stored per-transport"

  ;; Verify two connections with different close-thunks are independent
  (let* ((called-a #f)
         (called-b #f)
         (conn-a ((@@ (hegel server) %make-hegel-connection)
                  (open-input-file "/dev/null")
                  (open-output-file "/dev/null")
                  (lambda () (set! called-a #t))
                  'ctl-a 'mux-a "0.7" 1))
         (conn-b ((@@ (hegel server) %make-hegel-connection)
                  (open-input-file "/dev/null")
                  (open-output-file "/dev/null")
                  (lambda () (set! called-b #t))
                  'ctl-b 'mux-b "0.7" 1)))
    ;; Close only conn-a
    (close-hegel-connection! conn-a)
    (test-assert "conn-a close-thunk was called" called-a)
    (test-assert "conn-b close-thunk was NOT called" (not called-b))
    ;; Now close conn-b
    (close-hegel-connection! conn-b)
    (test-assert "conn-b close-thunk was called after explicit close" called-b)))

;;;; ── make-hegel-connection (SKIPPED — requires live server) ───────────────
;;
;; Full make-hegel-connection with #:transport keyword requires a live
;; hegel-core server. The transport dispatch logic is verified above
;; via hegel-transport. Integration tests should cover:
;;   (make-hegel-connection #:transport 'stdio)
;;   (make-hegel-connection #:transport 'socket)

(test-end "server")
