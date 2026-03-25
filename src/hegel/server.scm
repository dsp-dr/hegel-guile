;;; hegel/server.scm — Lifecycle: spawn hegel-core and connect

(define-module (hegel server)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-11)
  #:use-module (hegel protocol)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
  #:export (make-hegel-connection
            hegel-connection-port
            close-hegel-connection!))

(define %hegel-version "0.1.0")
(define %client-name   "hegel-guile")

;;;; ── Data types ─────────────────────────────────────────────────────────────

(define-record-type <hegel-connection>
  (%make-hegel-connection port proc server-version)
  hegel-connection?
  (port           hegel-connection-port)
  (proc           hegel-connection-proc)
  (server-version hegel-connection-server-version))

;;;; ── Server resolution ───────────────────────────────────────────────────────

(define (find-hegel-command)
  "Return the hegel-core command to use."
  (or (getenv "HEGEL_SERVER_COMMAND")
      ;; Try uv tool run (preferred)
      (and (zero? (system "uv --version >/dev/null 2>&1"))
           "uv tool run hegel")
      ;; Fall back to PATH lookup
      (let ((p (open-input-pipe "command -v hegel 2>/dev/null")))
        (let ((path (read-line p)))
          (close-pipe p)
          (if (eof-object? path) #f (string-trim-right path))))
      (error "hegel-guile: cannot find hegel-core. Install via: uv tool install hegel-core\nOr set HEGEL_SERVER_COMMAND.")))

;;;; ── Socket connection ───────────────────────────────────────────────────────

(define (connect-unix-socket path)
  "Open a binary input/output port connected to the Unix socket at PATH."
  (let ((sock (socket AF_UNIX SOCK_STREAM 0)))
    (connect sock AF_UNIX path)
    ;; Wrap the socket in binary buffered ports
    (let ((port (socket->port sock)))
      port)))

;; Guile doesn't expose socket->port directly in all versions; we use
;; the fd-based approach for portability.
(define (socket->port sock)
  (let ((fd (fileno sock)))
    ;; Duplicate fd so close-port doesn't close the socket fd we need
    (let ((in  (fdopen (dup fd) "rb"))
          (out (fdopen (dup fd) "wb")))
      ;; Return a composite binary port; for protocol send/recv we use
      ;; separate in/out. We store both in a vector.
      (vector in out sock))))

;;;; ── Startup ─────────────────────────────────────────────────────────────────

(define (spawn-server cmd)
  "Spawn CMD, return (values proc stdout-port).
   The server writes the socket path as a single line to stdout."
  ;; popen gives us a text port for stdout; we read the socket path from it.
  (let* ((full-cmd (string-append cmd " 2>/tmp/hegel-server.log"))
         (pipe     (open-input-pipe full-cmd)))
    ;; Read the socket path line
    (let ((path (read-line pipe)))
      (when (eof-object? path)
        (error "hegel-guile: server did not write socket path to stdout"))
      (values pipe (string-trim-right path)))))

(define (make-hegel-connection)
  "Spawn hegel-core, connect to its Unix socket, perform handshake.
   Returns a <hegel-connection>."
  (let ((cmd (find-hegel-command)))
    (let-values (((proc socket-path) (spawn-server cmd)))
      ;; Give the server a moment to bind
      (usleep 100000)
      (let* ((conn-vec  (connect-unix-socket socket-path))
             (in-port   (vector-ref conn-vec 0))
             (out-port  (vector-ref conn-vec 1))
             ;; We pass around a cons of (in . out) as the "port"
             (port      (cons in-port out-port)))
        ;; Handshake
        (send-message! out-port (msg-handshake %client-name %hegel-version))
        (let ((resp (recv-message! in-port)))
          (unless (equal? (response-type resp) "handshake")
            (error "hegel-guile: unexpected handshake response" resp))
          (%make-hegel-connection port proc
                                  (response-server-version resp)))))))

(define (close-hegel-connection! conn)
  (let* ((port     (hegel-connection-port conn))
         (in-port  (car port))
         (out-port (cdr port)))
    (close-port in-port)
    (close-port out-port)
    (close-pipe (hegel-connection-proc conn))))
