;;; hegel/server.scm — Lifecycle: spawn hegel-core, connect, handshake
;;;
;;; The actual protocol (hegel-core 0.2.3):
;;;   - Client creates socket path, passes as CLI argument
;;;   - Handshake: raw bytes "hegel_handshake_start" on channel 0
;;;   - Server replies with raw bytes "Hegel/{version}"
;;;   - All subsequent communication uses HEGL packet framing
;;;   - Post-handshake traffic is multiplexed (C-011, C-014)

(define-module (hegel server)
  #:use-module (hegel protocol)
  #:use-module (hegel channel)
  #:use-module (hegel packet)
  #:use-module (hegel mux)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-11)
  #:export (make-hegel-connection
            hegel-connection?
            hegel-connection-control-channel
            hegel-connection-mux
            hegel-connection-in-port
            hegel-connection-out-port
            hegel-connection-server-version
            hegel-connection-next-test-channel!
            hegel-connection-next-test-channel-id!
            close-hegel-connection!))

(define %client-name "hegel-guile")

;;;; ── Data types ─────────────────────────────────────────────────────────────

(define-record-type <hegel-connection>
  (%make-hegel-connection in-port out-port socket-obj proc
                          control-channel mux server-version channel-counter)
  hegel-connection?
  (in-port         hegel-connection-in-port)
  (out-port        hegel-connection-out-port)
  (socket-obj      hegel-connection-socket-obj)
  (proc            hegel-connection-proc)
  (control-channel hegel-connection-control-channel)
  (mux             hegel-connection-mux)
  (server-version  hegel-connection-server-version)
  (channel-counter hegel-connection-channel-counter
                   set-hegel-connection-channel-counter!))

(define (hegel-connection-next-test-channel! conn)
  "Allocate and return a new muxed test-case channel on this connection."
  (let* ((n (hegel-connection-channel-counter conn))
         (channel-id (make-client-channel-id n))
         (channel (make-muxed-channel channel-id (hegel-connection-mux conn))))
    (set-hegel-connection-channel-counter! conn (+ n 1))
    channel))

(define (hegel-connection-next-test-channel-id! conn)
  "Allocate and return the next client test channel ID (odd integer).
Does not create a channel object — used when the caller will create
muxed channels separately (e.g., for server-driven test case lifecycle)."
  (let* ((n (hegel-connection-channel-counter conn))
         (channel-id (make-client-channel-id n)))
    (set-hegel-connection-channel-counter! conn (+ n 1))
    channel-id))

;;;; ── Server resolution ─────────────────────────────────────────────────────

(define (find-hegel-command)
  "Return the hegel-core command to use."
  (or (getenv "HEGEL_SERVER_COMMAND")
      (and (zero? (system "uv --version >/dev/null 2>&1"))
           "uv tool run hegel")
      (let ((p (open-input-pipe "command -v hegel 2>/dev/null")))
        (let ((path (read-line p)))
          (close-pipe p)
          (if (eof-object? path) #f (string-trim-right path))))
      (error "hegel-guile: cannot find hegel-core. Install via: uv tool install hegel-core\nOr set HEGEL_SERVER_COMMAND.")))

;;;; ── Socket connection ─────────────────────────────────────────────────────

(define (make-socket-path)
  "Create a unique socket path in the system temp directory."
  (let ((tmpdir (or (getenv "TMPDIR") "/tmp")))
    (string-append tmpdir "/hegel-guile-" (number->string (getpid)) ".sock")))

(define (connect-unix-socket path)
  "Connect to Unix socket at PATH. Returns (values in-port out-port socket)."
  (let ((sock (socket AF_UNIX SOCK_STREAM 0)))
    (connect sock AF_UNIX path)
    (let* ((fd (fileno sock))
           (in-port  (fdopen (dup fd) "rb"))
           (out-port (fdopen (dup fd) "wb")))
      ;; Disable buffering for binary protocol
      (setvbuf in-port 'none)
      (setvbuf out-port 'none)
      (values in-port out-port sock))))

(define (wait-for-socket path timeout-ms)
  "Poll for PATH to exist, sleeping 50ms between checks. Error after TIMEOUT-MS."
  (let loop ((elapsed 0))
    (cond
     ((file-exists? path) #t)
     ((>= elapsed timeout-ms)
      (error "hegel-guile: server did not create socket within timeout" path))
     (else
      (usleep 50000)  ; 50ms
      (loop (+ elapsed 50))))))

;;;; ── Startup ───────────────────────────────────────────────────────────────

(define (spawn-server cmd socket-path)
  "Spawn hegel-core with SOCKET-PATH as CLI argument.
Returns the pipe (for cleanup via close-pipe)."
  (let* ((full-cmd (string-append cmd " " socket-path " 2>/tmp/hegel-server.log"))
         (pipe (open-input-pipe full-cmd)))
    pipe))

(define (perform-handshake control-channel)
  "Send handshake on CONTROL-CHANNEL, validate server version.
Returns the server version number."
  (let ((msg-id (channel-send-raw! control-channel %handshake-string)))
    (let ((reply-payload (channel-recv-raw! control-channel msg-id)))
      (parse-server-version reply-payload))))

(define (make-hegel-connection)
  "Spawn hegel-core, connect to its Unix socket, perform handshake.
After handshake, creates a connection mux for multiplexed channel traffic.
Returns a <hegel-connection>."
  (let* ((cmd         (find-hegel-command))
         (socket-path (make-socket-path))
         (proc        (spawn-server cmd socket-path)))
    ;; Wait for server to create the socket file
    (wait-for-socket socket-path 10000)
    (let-values (((in-port out-port sock) (connect-unix-socket socket-path)))
      ;; Handshake uses direct (non-muxed) channel — no interleaving yet
      (let* ((direct-control (make-hegel-channel 0 in-port out-port))
             (version (perform-handshake direct-control))
             ;; After handshake, create mux for all subsequent traffic
             (mux (make-connection-mux in-port out-port))
             ;; Re-create control channel in muxed mode
             (control (make-muxed-channel 0 mux)))
        ;; Clean up socket file
        (catch #t
          (lambda () (delete-file socket-path))
          (lambda _ #f))
        (%make-hegel-connection in-port out-port sock proc
                                control mux version 1)))))

(define (close-hegel-connection! conn)
  "Close the connection and terminate the server process."
  (catch #t
    (lambda ()
      (close-port (hegel-connection-in-port conn))
      (close-port (hegel-connection-out-port conn)))
    (lambda _ #f))
  (catch #t
    (lambda ()
      (close-pipe (hegel-connection-proc conn)))
    (lambda _ #f)))
