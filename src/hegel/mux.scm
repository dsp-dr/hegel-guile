;;; hegel/mux.scm — Connection multiplexer for interleaved channel traffic
;;;
;;; C-011: hegel-core multiplexes packets from different channels on a single
;;; socket.  When channel-recv-reply! reads the next packet, it may get a
;;; packet meant for a different channel.  The mux reads packets from the
;;; wire and buffers them per-channel, so each channel sees only its own
;;; traffic in FIFO order.

(define-module (hegel mux)
  #:use-module (hegel packet)
  #:use-module (hegel cbor)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (srfi srfi-9)
  #:export (make-connection-mux
            connection-mux?
            connection-mux-in-port
            connection-mux-out-port
            mux-read-for-channel!
            mux-write-packet!))

;;;; ── Record ─────────────────────────────────────────────────────────────────

(define-record-type <connection-mux>
  (%make-connection-mux in-port out-port buffers)
  connection-mux?
  (in-port  connection-mux-in-port)
  (out-port connection-mux-out-port)
  (buffers  connection-mux-buffers))

(define (make-connection-mux in-port out-port)
  "Create a connection multiplexer over the given ports.
BUFFERS is a hash table mapping channel-id -> list of buffered packets (FIFO)."
  (%make-connection-mux in-port out-port (make-hash-table)))

;;;; ── Buffer operations ──────────────────────────────────────────────────────

(define (buffer-ref buffers channel-id)
  "Return the packet queue for CHANNEL-ID, or '() if empty."
  (or (hashv-ref buffers channel-id) '()))

(define (buffer-push! buffers channel-id packet)
  "Append PACKET to the end of the queue for CHANNEL-ID (FIFO)."
  (let ((queue (buffer-ref buffers channel-id)))
    (hashv-set! buffers channel-id (append queue (list packet)))))

(define (buffer-pop! buffers channel-id)
  "Remove and return the first packet from the queue for CHANNEL-ID.
Returns #f if the queue is empty."
  (let ((queue (buffer-ref buffers channel-id)))
    (if (null? queue)
        #f
        (begin
          (hashv-set! buffers channel-id (cdr queue))
          (car queue)))))

;;;; ── Read with demux ────────────────────────────────────────────────────────

(define (mux-read-for-channel! mux channel-id)
  "Read the next packet destined for CHANNEL-ID.
If the buffer already contains a packet for CHANNEL-ID, return it immediately.
Otherwise, read packets from the wire, buffering packets for other channels,
until one for CHANNEL-ID arrives."
  (let ((buffers (connection-mux-buffers mux)))
    ;; Check buffer first
    (let ((buffered (buffer-pop! buffers channel-id)))
      (if buffered
          buffered
          ;; Read from wire until we find one for our channel
          (let loop ()
            (let ((packet (read-hegl-packet! (connection-mux-in-port mux))))
              (if (= (hegl-packet-channel-id packet) channel-id)
                  packet
                  (begin
                    (buffer-push! buffers (hegl-packet-channel-id packet) packet)
                    (loop)))))))))

;;;; ── Write (pass-through) ───────────────────────────────────────────────────

(define (mux-write-packet! mux packet)
  "Write PACKET to the mux's output port."
  (write-hegl-packet! (connection-mux-out-port mux) packet))
