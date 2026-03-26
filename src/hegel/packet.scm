;;; hegel/packet.scm — HEGL packet framing
;;;
;;; Wire format (from hegeldev/hegel-rust src/protocol/packet.rs):
;;;   [4B magic 0x4845474C][4B CRC32][4B channel_id][4B message_id][4B payload_len]
;;;   [NB payload][1B terminator 0x0A]
;;;
;;; CRC32 is computed over the 20-byte header (with checksum field zeroed)
;;; concatenated with the payload.

(define-module (hegel packet)
  #:use-module (hegel crc32)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (srfi srfi-9)
  #:export (%hegl-magic
            %hegl-terminator
            %reply-bit
            %channel-close-id
            %channel-close-payload
            make-hegl-packet
            hegl-packet?
            hegl-packet-channel-id
            hegl-packet-message-id
            hegl-packet-is-reply?
            hegl-packet-payload
            write-hegl-packet!
            read-hegl-packet!))

;;;; ── Constants ────────────────────────────────────────────────────────────────

(define %hegl-magic      #x4845474C)  ; "HEGL"
(define %hegl-terminator #x0A)
(define %reply-bit       (ash 1 31))  ; bit 31 of message_id
(define %header-size     20)

;; Channel close: message_id = (reply-bit - 1), payload = #xFE
(define %channel-close-id      (- %reply-bit 1))
(define %channel-close-payload (make-bytevector 1 #xFE))

;;;; ── Record ───────────────────────────────────────────────────────────────────

(define-record-type <hegl-packet>
  (%make-hegl-packet channel-id message-id payload)
  hegl-packet?
  (channel-id  hegl-packet-channel-id)
  (message-id  hegl-packet-message-id)
  (payload     hegl-packet-payload))

(define (make-hegl-packet channel-id message-id payload)
  (%make-hegl-packet channel-id message-id payload))

(define (hegl-packet-is-reply? packet)
  (not (zero? (logand (hegl-packet-message-id packet) %reply-bit))))

;;;; ── Write ────────────────────────────────────────────────────────────────────

(define (write-hegl-packet! port packet)
  "Write PACKET to binary PORT in HEGL wire format."
  (let* ((payload    (hegl-packet-payload packet))
         (payload-len (bytevector-length payload))
         (header     (make-bytevector %header-size 0)))
    ;; Build header with checksum field zeroed
    (bytevector-u32-set! header 0  %hegl-magic (endianness big))
    ;; bytes 4-7: checksum = 0 for now
    (bytevector-u32-set! header 8  (hegl-packet-channel-id packet) (endianness big))
    (bytevector-u32-set! header 12 (hegl-packet-message-id packet) (endianness big))
    (bytevector-u32-set! header 16 payload-len (endianness big))
    ;; Compute CRC32 over header (checksum zeroed) + payload
    (let* ((crc-state (crc32-update #xFFFFFFFF header))
           (crc-state (crc32-update crc-state payload))
           (checksum  (logand (logxor crc-state #xFFFFFFFF) #xFFFFFFFF)))
      ;; Patch checksum into header
      (bytevector-u32-set! header 4 checksum (endianness big))
      ;; Write: header + payload + terminator
      (put-bytevector port header)
      (put-bytevector port payload)
      (put-u8 port %hegl-terminator)
      (force-output port))))

;;;; ── Read ─────────────────────────────────────────────────────────────────────

(define (read-exact! port n what)
  "Read exactly N bytes from PORT. Raise error with WHAT context on failure."
  (let ((bv (get-bytevector-n port n)))
    (when (eof-object? bv)
      (error (string-append "hegl-packet: EOF reading " what)))
    (when (< (bytevector-length bv) n)
      (error (string-append "hegl-packet: short read on " what)
             n (bytevector-length bv)))
    bv))

(define (read-hegl-packet! port)
  "Read one HEGL packet from binary PORT. Validates magic, CRC32, terminator."
  (let* ((header (read-exact! port %header-size "header"))
         (magic  (bytevector-u32-ref header 0 (endianness big))))
    ;; Validate magic
    (unless (= magic %hegl-magic)
      (error "hegl-packet: bad magic" magic %hegl-magic))
    (let* ((received-crc (bytevector-u32-ref header 4  (endianness big)))
           (channel-id   (bytevector-u32-ref header 8  (endianness big)))
           (message-id   (bytevector-u32-ref header 12 (endianness big)))
           (payload-len  (bytevector-u32-ref header 16 (endianness big)))
           (payload      (if (zero? payload-len)
                             (make-bytevector 0)
                             (read-exact! port payload-len "payload")))
           (terminator   (get-u8 port)))
      ;; Validate terminator
      (when (eof-object? terminator)
        (error "hegl-packet: EOF reading terminator"))
      (unless (= terminator %hegl-terminator)
        (error "hegl-packet: bad terminator" terminator))
      ;; Validate CRC32: zero the checksum field in header, compute over header+payload
      (let ((header-copy (bytevector-copy header)))
        (bytevector-u32-set! header-copy 4 0 (endianness big))
        (let* ((crc-state (crc32-update #xFFFFFFFF header-copy))
               (crc-state (crc32-update crc-state payload))
               (computed  (logand (logxor crc-state #xFFFFFFFF) #xFFFFFFFF)))
          (unless (= computed received-crc)
            (error "hegl-packet: CRC32 mismatch" computed received-crc))))
      ;; Return packet
      (make-hegl-packet channel-id message-id payload))))
