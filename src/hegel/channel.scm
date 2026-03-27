;;; hegel/channel.scm — Multiplexed channel over HEGL packets
;;;
;;; The Hegel protocol multiplexes logical channels over a single socket.
;;; Channel 0 is the control channel (handshake, run_test).
;;; Client channels use odd IDs: (logior (ash n 1) 1).
;;; Server channels use even IDs: (ash n 1).
;;;
;;; Channels can operate in two modes:
;;;   1. Direct mode (make-hegel-channel): reads/writes packets on raw ports.
;;;      Assumes the caller owns the port and no interleaving occurs.
;;;   2. Muxed mode (make-muxed-channel): reads/writes through a
;;;      <connection-mux> that buffers packets for other channels.

(define-module (hegel channel)
  #:use-module (hegel packet)
  #:use-module (hegel cbor)
  #:use-module (hegel mux)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (srfi srfi-9)
  #:export (make-hegel-channel
            make-muxed-channel
            hegel-channel?
            hegel-channel-id
            hegel-channel-mux
            channel-next-message-id!
            channel-send-request!
            channel-recv-reply!
            channel-send-raw!
            channel-recv-raw!
            channel-send-cbor!
            channel-recv-cbor!
            channel-write-reply!
            channel-write-reply-error!
            channel-close!
            make-client-channel-id))

;;;; ── Channel record ───────────────────────────────────────────────────────────

(define-record-type <hegel-channel>
  (%make-hegel-channel id in-port out-port msg-counter mux)
  hegel-channel?
  (id          hegel-channel-id)
  (in-port     hegel-channel-in-port)
  (out-port    hegel-channel-out-port)
  (msg-counter hegel-channel-msg-counter set-hegel-channel-msg-counter!)
  (mux         hegel-channel-mux))

(define (make-hegel-channel channel-id in-port out-port)
  "Create a channel in direct mode (no multiplexer)."
  (%make-hegel-channel channel-id in-port out-port 0 #f))

(define (make-muxed-channel channel-id mux)
  "Create a channel that reads/writes through a connection multiplexer.
The channel uses the mux's ports for I/O, buffering packets for other channels."
  (%make-hegel-channel channel-id
                       (connection-mux-in-port mux)
                       (connection-mux-out-port mux)
                       0
                       mux))

(define (channel-next-message-id! channel)
  "Allocate and return the next message ID for this channel."
  (let ((current (hegel-channel-msg-counter channel)))
    (set-hegel-channel-msg-counter! channel (+ current 1))
    (+ current 1)))

;;;; ── Client channel ID encoding ───────────────────────────────────────────────

(define (make-client-channel-id n)
  "Encode client channel number N as a wire channel ID (odd)."
  (logior (ash n 1) 1))

;;;; ── Raw send/recv (for handshake) ────────────────────────────────────────────

(define (channel-send-raw! channel payload)
  "Send raw bytes PAYLOAD as a request on CHANNEL. Returns message ID used.
In muxed mode, writes through the mux; in direct mode, writes to the port."
  (let* ((msg-id  (channel-next-message-id! channel))
         (packet  (make-hegl-packet (hegel-channel-id channel)
                                    msg-id
                                    payload))
         (mux     (hegel-channel-mux channel)))
    (if mux
        (mux-write-packet! mux packet)
        (write-hegl-packet! (hegel-channel-out-port channel) packet))
    msg-id))

(define (channel-recv-raw! channel expected-msg-id)
  "Read a reply packet on CHANNEL, validate it matches EXPECTED-MSG-ID.
Returns the raw payload bytevector.
In muxed mode, reads through the mux (which buffers packets for other channels);
in direct mode, reads from the port."
  (let* ((mux (hegel-channel-mux channel))
         (pkt (if mux
                  (mux-read-for-channel! mux (hegel-channel-id channel))
                  (read-hegl-packet! (hegel-channel-in-port channel)))))
    (unless (hegl-packet-is-reply? pkt)
      (error "channel: expected reply packet" pkt))
    (let ((reply-id (logand (hegl-packet-message-id pkt)
                            (lognot %reply-bit))))
      (unless (= reply-id expected-msg-id)
        (error "channel: message ID mismatch" expected-msg-id reply-id)))
    (hegl-packet-payload pkt)))

;;;; ── CBOR send/recv ───────────────────────────────────────────────────────────

(define (channel-send-cbor! channel value)
  "Encode VALUE as CBOR and send as a request. Returns message ID."
  (channel-send-raw! channel (cbor-encode value)))

(define (channel-recv-cbor! channel expected-msg-id)
  "Read a CBOR reply on CHANNEL.  Unwraps the {\"result\": value} envelope.
If the payload contains an \"error\" key, raises with the error message and type.
Returns the unwrapped result value.

C-010: All reply payloads from hegel-core are CBOR maps with either
  {\"result\": value} or {\"error\": msg, \"type\": name}.
Bare CBOR values are a protocol violation."
  (let ((decoded (cbor-decode (channel-recv-raw! channel expected-msg-id))))
    (cond
     ((and (pair? decoded) (assoc "error" decoded))
      => (lambda (err-pair)
           (let ((err-type (let ((tp (assoc "type" decoded)))
                             (if tp (cdr tp) "unknown"))))
             (error (string-append "hegel-core error (" err-type ")")
                    (cdr err-pair)))))
     ((and (pair? decoded) (assoc "result" decoded))
      => (lambda (result-pair) (cdr result-pair)))
     (else
      (error "channel: reply payload missing \"result\" key (C-010 violation)"
             decoded)))))

;;;; ── Reply writers (C-010: envelope with {"result": ...} or {"error": ...}) ──

(define (channel-write-reply! channel message-id value)
  "Write a reply packet on CHANNEL for MESSAGE-ID with payload {\"result\": VALUE}.
The reply bit is set on the message ID per HEGL wire format."
  (let* ((payload (cbor-encode (list (cons "result" value))))
         (packet  (make-hegl-packet (hegel-channel-id channel)
                                    (logior message-id %reply-bit)
                                    payload))
         (mux     (hegel-channel-mux channel)))
    (if mux
        (mux-write-packet! mux packet)
        (write-hegl-packet! (hegel-channel-out-port channel) packet))))

(define (channel-write-reply-error! channel message-id error-msg error-type)
  "Write an error reply packet on CHANNEL for MESSAGE-ID.
Payload is {\"error\": ERROR-MSG, \"type\": ERROR-TYPE}."
  (let* ((payload (cbor-encode (list (cons "error" error-msg)
                                     (cons "type" error-type))))
         (packet  (make-hegl-packet (hegel-channel-id channel)
                                    (logior message-id %reply-bit)
                                    payload))
         (mux     (hegel-channel-mux channel)))
    (if mux
        (mux-write-packet! mux packet)
        (write-hegl-packet! (hegel-channel-out-port channel) packet))))

;;;; ── Convenience: send request, wait for reply ────────────────────────────────

(define (channel-send-request! channel value)
  "Send CBOR VALUE as request, wait for CBOR reply. Returns decoded reply."
  (let ((msg-id (channel-send-cbor! channel value)))
    (channel-recv-cbor! channel msg-id)))

;;;; ── Channel close ────────────────────────────────────────────────────────────

(define (channel-close! channel)
  "Send channel close packet."
  (let* ((packet (make-hegl-packet (hegel-channel-id channel)
                                   %channel-close-id
                                   %channel-close-payload))
         (mux    (hegel-channel-mux channel)))
    (if mux
        (mux-write-packet! mux packet)
        (write-hegl-packet! (hegel-channel-out-port channel) packet))))
