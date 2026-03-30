;;; hegel/server.scm — Lifecycle: spawn hegel-core, connect, handshake
;;;
;;; Transport selection via HEGEL_TRANSPORT env var or #:transport keyword:
;;;   "stdio"  — hegel --stdio, HEGL packets on stdin/stdout (default, 0.2.3+)
;;;   "socket" — hegel <path>, HEGL packets on Unix socket (legacy)
;;;
;;; Both transports use identical HEGL packet framing and protocol.
;;; The handshake, mux, and channel layers are transport-agnostic.

(define-module (hegel server)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-11)
  #:use-module (hegel protocol)
  #:use-module (hegel channel)
  #:use-module (hegel packet)
  #:use-module (hegel mux)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
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
  (%make-hegel-connection in-port out-port close-thunk
                          control-channel mux server-version channel-counter)
  hegel-connection?
  (in-port         hegel-connection-in-port)
  (out-port        hegel-connection-out-port)
  (close-thunk     hegel-connection-close-thunk)  ; transport-specific cleanup
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

;;;; ── Transport selection ───────────────────────────────────────────────────

(define (hegel-transport)
  "Return the transport mode: 'stdio or 'socket."
  (let ((env (getenv "HEGEL_TRANSPORT")))
    (cond
     ((not env) 'stdio)
     ((string=? env "stdio") 'stdio)
     ((string=? env "socket") 'socket)
     (else (error "hegel-guile: HEGEL_TRANSPORT must be 'stdio' or 'socket'" env)))))

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

;;;; ── Shared post-connect logic ────────────────────────────────────────────

(define (perform-handshake control-channel)
  "Send handshake on CONTROL-CHANNEL, validate server version."
  (let ((msg-id (channel-send-raw! control-channel %handshake-string)))
    (let ((reply-payload (channel-recv-raw! control-channel msg-id)))
      (parse-server-version reply-payload))))

(define (finalize-connection in-port out-port close-thunk)
  "Handshake, create mux, build connection record. Shared by all transports."
  (let* ((direct-control (make-hegel-channel 0 in-port out-port))
         (version (perform-handshake direct-control))
         (mux (make-connection-mux in-port out-port))
         (control (make-muxed-channel 0 mux)))
    (%make-hegel-connection in-port out-port close-thunk
                            control mux version 1)))

;;;; ── stdio transport ──────────────────────────────────────────────────────
;;
;; Uses pipe + primitive-fork + execlp instead of open-input-output-pipe,
;; which segfaults on FreeBSD Guile 3.x. Gives us separate read/write
;; ports and the child PID for clean waitpid cleanup.

(define (spawn-server-stdio cmd)
  "Spawn hegel-core in --stdio mode via pipe+fork.
Returns (values in-port out-port child-pid)."
  (let-values (((child-read parent-write) (pipe))    ; parent writes → child reads (child stdin)
               ((parent-read child-write) (pipe)))    ; child writes → parent reads (child stdout)
    (let ((pid (primitive-fork)))
      (if (zero? pid)
          ;; Child: wire up stdin/stdout, exec hegel
          (begin
            (close-port parent-write)
            (close-port parent-read)
            ;; Redirect child-read → stdin (fd 0)
            (dup2 (fileno child-read) 0)
            (close-port child-read)
            ;; Redirect child-write → stdout (fd 1)
            (dup2 (fileno child-write) 1)
            (close-port child-write)
            ;; Redirect stderr to /dev/null
            (let ((devnull (open-fdes "/dev/null" O_WRONLY)))
              (dup2 devnull 2)
              (close-fdes devnull))
            ;; Exec: split cmd into program + args
            (let ((args (string-split
                         (string-append cmd " --stdio --verbosity quiet")
                         #\space)))
              (apply execlp (car args) args)))
          ;; Parent: close child's ends, wrap in binary ports
          (begin
            (close-port child-read)
            (close-port child-write)
            (let ((in-port  (fdopen (fileno parent-read) "rb"))
                  (out-port (fdopen (fileno parent-write) "wb")))
              (setvbuf in-port 'none)
              (setvbuf out-port 'none)
              (values in-port out-port pid)))))))

(define (make-hegel-connection/stdio cmd)
  "Connect via stdio transport (hegel --stdio)."
  (let-values (((in-port out-port pid) (spawn-server-stdio cmd)))
    (finalize-connection
     in-port out-port
     (lambda ()
       ;; Close ports, then reap child process
       (catch #t (lambda () (close-port in-port)) (lambda _ #f))
       (catch #t (lambda () (close-port out-port)) (lambda _ #f))
       (catch #t (lambda () (waitpid pid)) (lambda _ #f))))))

;;;; ── Socket transport (legacy) ────────────────────────────────────────────

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
      (setvbuf in-port 'none)
      (setvbuf out-port 'none)
      (values in-port out-port sock))))

(define (wait-for-socket path timeout-ms)
  "Poll for PATH to exist, sleeping 50ms between checks. Error after TIMEOUT-MS."
  (let loop ((elapsed 0))  ; elapsed in ms
    (cond
     ((file-exists? path) #t)
     ((>= elapsed timeout-ms)
      (error "hegel-guile: server did not create socket within timeout" path))
     (else
      (usleep 50000)  ; 50ms
      (loop (+ elapsed 50))))))

(define (spawn-server-socket cmd socket-path)
  "Spawn hegel-core with SOCKET-PATH as CLI argument in background."
  (let* ((full-cmd (string-append cmd " " socket-path
                                  " --verbosity quiet"
                                  " 2>/dev/null &"))
         (pipe (open-input-pipe full-cmd)))
    pipe))

(define (make-hegel-connection/socket cmd)
  "Connect via Unix socket transport (legacy)."
  (let* ((socket-path (make-socket-path))
         (proc        (spawn-server-socket cmd socket-path)))
    (wait-for-socket socket-path 10000)
    (let-values (((in-port out-port sock) (connect-unix-socket socket-path)))
      (catch #t
        (lambda () (delete-file socket-path))
        (lambda _ #f))
      (finalize-connection
       in-port out-port
       (lambda ()
         ;; Close ports, socket, and reap shell process
         (catch #t (lambda () (close-port in-port)) (lambda _ #f))
         (catch #t (lambda () (close-port out-port)) (lambda _ #f))
         (catch #t (lambda () (close-port sock)) (lambda _ #f))
         (catch #t (lambda () (close-pipe proc)) (lambda _ #f)))))))

;;;; ── Public API ───────────────────────────────────────────────────────────

(define* (make-hegel-connection #:key (transport (hegel-transport)))
  "Spawn hegel-core, connect via TRANSPORT, perform handshake.
TRANSPORT is 'stdio (default) or 'socket. Can also be set via HEGEL_TRANSPORT
env var. After handshake, creates a connection mux for multiplexed traffic.
Returns a <hegel-connection>."
  (let ((cmd (find-hegel-command)))
    (case transport
      ((stdio)  (make-hegel-connection/stdio cmd))
      ((socket) (make-hegel-connection/socket cmd))
      (else     (error "hegel-guile: unknown transport" transport)))))

(define (close-hegel-connection! conn)
  "Close the connection and terminate the server process.
Calls the transport-specific close thunk stored at construction time."
  ((hegel-connection-close-thunk conn)))
