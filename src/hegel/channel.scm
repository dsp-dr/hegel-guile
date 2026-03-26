;;; hegel/channel.scm — Multiplexed channel over HEGL packets
;;;
;;; The Hegel protocol multiplexes logical channels over a single socket.
;;; Channel 0 is the control channel (handshake, run_test).
;;; Client channels use odd IDs: (logior (ash n 1) 1).
;;; Server channels use even IDs: (ash n 1).

(define-module (hegel channel)
  #:use-module (hegel packet)
  #:use-module (hegel cbor)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (srfi srfi-9)
  #:export (make-hegel-channel
            hegel-channel?
            hegel-channel-id
            channel-next-message-id!
            channel-send-request!
            channel-recv-reply!
            channel-send-raw!
            channel-recv-raw!
            channel-send-cbor!
            channel-recv-cbor!
            channel-close!
            make-client-channel-id))

;;;; ── Channel record ───────────────────────────────────────────────────────────

(define-record-type <hegel-channel>
  (%make-hegel-channel id in-port out-port msg-counter)
  hegel-channel?
  (id          hegel-channel-id)
  (in-port     hegel-channel-in-port)
  (out-port    hegel-channel-out-port)
  (msg-counter hegel-channel-msg-counter set-hegel-channel-msg-counter!))

(define (make-hegel-channel channel-id in-port out-port)
  (%make-hegel-channel channel-id in-port out-port 0))

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
  "Send raw bytes PAYLOAD as a request on CHANNEL. Returns message ID used."
  (let ((msg-id (channel-next-message-id! channel)))
    (write-hegl-packet! (hegel-channel-out-port channel)
                        (make-hegl-packet (hegel-channel-id channel)
                                          msg-id
                                          payload))
    msg-id))

(define (channel-recv-raw! channel expected-msg-id)
  "Read a reply packet on CHANNEL, validate it matches EXPECTED-MSG-ID.
Returns the raw payload bytevector."
  (let ((pkt (read-hegl-packet! (hegel-channel-in-port channel))))
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
  "Read a CBOR reply on CHANNEL. Returns the decoded value."
  (cbor-decode (channel-recv-raw! channel expected-msg-id)))

;;;; ── Convenience: send request, wait for reply ────────────────────────────────

(define (channel-send-request! channel value)
  "Send CBOR VALUE as request, wait for CBOR reply. Returns decoded reply."
  (let ((msg-id (channel-send-cbor! channel value)))
    (channel-recv-cbor! channel msg-id)))

;;;; ── Channel close ────────────────────────────────────────────────────────────

(define (channel-close! channel)
  "Send channel close packet."
  (write-hegl-packet! (hegel-channel-out-port channel)
                      (make-hegl-packet (hegel-channel-id channel)
                                        %channel-close-id
                                        %channel-close-payload)))
