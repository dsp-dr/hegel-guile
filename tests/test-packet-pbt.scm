;;; tests/test-packet-pbt.scm — PBT-style round-trip property tests for packet framing
;;; Bead: hegel-guile-x99 (self-host PBT)
;;;
;;; Tests HEGL packet encode/decode invariants over varied channel IDs,
;;; message IDs, payload sizes, and reply-bit combinations.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel packet)
             (hegel crc32)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports)
             (srfi srfi-11)
             (srfi srfi-64))

(test-begin "packet-pbt")

;;;; ── Helpers ─────────────────────────────────────────────────────────────────

(define (packet->bytevector packet)
  "Serialize PACKET to a bytevector via a bytevector output port."
  (let-values (((port get-bv) (open-bytevector-output-port)))
    (write-hegl-packet! port packet)
    (get-bv)))

(define (bytevector->packet bv)
  "Deserialize a HEGL packet from bytevector BV."
  (read-hegl-packet! (open-bytevector-input-port bv)))

(define (packet-round-trip channel-id message-id payload)
  "Create a packet, serialize, deserialize, return the result."
  (bytevector->packet
   (packet->bytevector
    (make-hegl-packet channel-id message-id payload))))

;;;; ── Property: channel-id is preserved for all valid values ─────────────────

(test-group "property: channel-id preservation"
  (let ((channel-ids '(0 1 2 127 128 255 256 65535 65536
                        16777215 4294967295)))
    (for-each
      (lambda (cid)
        (let* ((payload (string->utf8 "ch-test"))
               (pkt (packet-round-trip cid 1 payload)))
          (test-equal (format #f "channel-id ~a preserved" cid)
            cid (hegl-packet-channel-id pkt))))
      channel-ids)))

;;;; ── Property: message-id is preserved for all valid values ─────────────────

(test-group "property: message-id preservation"
  (let ((message-ids (list 0 1 2 255 256 65535 65536
                           (- %reply-bit 1)  ; max non-reply
                           %reply-bit         ; reply with id=0
                           (logior %reply-bit 1)
                           (logior %reply-bit 42)
                           (logior %reply-bit (- %reply-bit 1)))))
    (for-each
      (lambda (mid)
        (let* ((payload (string->utf8 "msg-test"))
               (pkt (packet-round-trip 0 mid payload)))
          (test-equal (format #f "message-id ~a preserved" mid)
            mid (hegl-packet-message-id pkt))))
      message-ids)))

;;;; ── Property: reply-bit detection ──────────────────────────────────────────

(test-group "property: reply-bit detection"
  ;; Non-reply message IDs
  (for-each
    (lambda (mid)
      (let ((pkt (packet-round-trip 0 mid (string->utf8 "x"))))
        (test-assert (format #f "message-id ~a is not a reply" mid)
          (not (hegl-packet-is-reply? pkt)))))
    '(0 1 42 255 65535))

  ;; Reply message IDs (bit 31 set)
  (for-each
    (lambda (mid)
      (let ((reply-mid (logior mid %reply-bit)))
        (let ((pkt (packet-round-trip 0 reply-mid (string->utf8 "x"))))
          (test-assert (format #f "message-id ~a|reply is a reply" mid)
            (hegl-packet-is-reply? pkt)))))
    '(0 1 42 255 65535)))

;;;; ── Property: payload preserved for varied sizes ───────────────────────────

(test-group "property: payload size preservation"
  (let ((sizes '(0 1 2 10 100 255 256 512 1024)))
    (for-each
      (lambda (size)
        (let* ((payload (make-bytevector size (modulo size 256)))
               (pkt (packet-round-trip 0 1 payload)))
          (test-equal (format #f "payload size=~a: length preserved" size)
            size (bytevector-length (hegl-packet-payload pkt)))
          (test-equal (format #f "payload size=~a: content preserved" size)
            payload (hegl-packet-payload pkt))))
      sizes)))

;;;; ── Property: payload content preserved for varied byte patterns ───────────

(test-group "property: payload content patterns"
  (let ((patterns
         (list
          ;; All zeros
          (make-bytevector 16 0)
          ;; All ones
          (make-bytevector 16 #xFF)
          ;; Ascending bytes
          (u8-list->bytevector
           (let loop ((i 0) (acc '()))
             (if (= i 16) (reverse acc) (loop (+ i 1) (cons i acc)))))
          ;; Descending bytes
          (u8-list->bytevector
           (let loop ((i 15) (acc '()))
             (if (< i 0) (reverse acc) (loop (- i 1) (cons i acc)))))
          ;; Alternating
          (u8-list->bytevector
           (let loop ((i 0) (acc '()))
             (if (= i 16) (reverse acc)
                 (loop (+ i 1) (cons (if (even? i) #x55 #xAA) acc))))))))
    (for-each
      (lambda (payload)
        (let ((pkt (packet-round-trip 0 1 payload)))
          (test-equal (format #f "payload pattern byte0=~a preserved"
                        (bytevector-u8-ref payload 0))
            payload (hegl-packet-payload pkt))))
      patterns)))

;;;; ── Property: wire format has correct structure ────────────────────────────

(test-group "property: wire format structure"
  (let ((sizes '(0 1 10 100 256)))
    (for-each
      (lambda (payload-size)
        (let* ((payload (make-bytevector payload-size #x42))
               (pkt (make-hegl-packet 0 1 payload))
               (wire (packet->bytevector pkt))
               ;; Expected: 20 header + payload-size + 1 terminator
               (expected-len (+ 20 payload-size 1)))
          (test-equal (format #f "wire size for payload=~a" payload-size)
            expected-len (bytevector-length wire))
          ;; Magic is always first 4 bytes
          (test-equal (format #f "magic for payload=~a" payload-size)
            #x4845474C
            (bytevector-u32-ref wire 0 (endianness big)))
          ;; Terminator is always last byte
          (test-equal (format #f "terminator for payload=~a" payload-size)
            #x0A
            (bytevector-u8-ref wire (- (bytevector-length wire) 1)))
          ;; Payload length field at offset 16
          (test-equal (format #f "payload-len field for payload=~a" payload-size)
            payload-size
            (bytevector-u32-ref wire 16 (endianness big)))))
      sizes)))

;;;; ── Property: CRC protects against single-bit corruption ──────────────────

(test-group "property: CRC detects single-bit corruption"
  (let* ((payload (string->utf8 "integrity-test"))
         (pkt (make-hegl-packet 0 1 payload))
         (wire (packet->bytevector pkt)))
    ;; Flip one bit in the payload region (starts at offset 20)
    ;; and verify the CRC check catches it
    (let loop ((bit-pos 0))
      (when (< bit-pos (* 8 (bytevector-length payload)))
        (let* ((corrupted (bytevector-copy wire))
               (byte-offset (+ 20 (quotient bit-pos 8)))
               (bit-mask (ash 1 (modulo bit-pos 8)))
               (original-byte (bytevector-u8-ref corrupted byte-offset)))
          (bytevector-u8-set! corrupted byte-offset
                              (logxor original-byte bit-mask))
          (test-error (format #f "bit ~a corruption detected" bit-pos)
            #t
            (bytevector->packet corrupted)))
        ;; Sample every 13th bit to keep test count manageable
        (loop (+ bit-pos 13))))))

;;;; ── Property: channel-close uses correct constants ─────────────────────────

(test-group "property: channel-close round-trip"
  (let* ((pkt (make-hegl-packet 0 %channel-close-id %channel-close-payload))
         (wire (packet->bytevector pkt))
         (pkt2 (bytevector->packet wire)))
    (test-equal "channel-close message-id preserved"
      %channel-close-id (hegl-packet-message-id pkt2))
    (test-equal "channel-close payload preserved"
      %channel-close-payload (hegl-packet-payload pkt2))
    (test-assert "channel-close is not a reply"
      (not (hegl-packet-is-reply? pkt2)))))

;;;; ── Property: multiple packets in sequence ─────────────────────────────────

(test-group "property: sequential packets"
  (let-values (((port get-bv) (open-bytevector-output-port)))
    ;; Write 5 packets with different payloads
    (let ((packets
           (map (lambda (i)
                  (make-hegl-packet i i (string->utf8 (format #f "pkt-~a" i))))
                '(0 1 2 3 4))))
      (for-each (lambda (pkt) (write-hegl-packet! port pkt)) packets)
      (let ((combined-bv (get-bv))
            (input-port #f))
        (set! input-port (open-bytevector-input-port combined-bv))
        ;; Read them back and verify order
        (for-each
          (lambda (i)
            (let ((pkt (read-hegl-packet! input-port)))
              (test-equal (format #f "sequential pkt ~a: channel-id" i)
                i (hegl-packet-channel-id pkt))
              (test-equal (format #f "sequential pkt ~a: payload" i)
                (string->utf8 (format #f "pkt-~a" i))
                (hegl-packet-payload pkt))))
          '(0 1 2 3 4))))))

(test-end "packet-pbt")
