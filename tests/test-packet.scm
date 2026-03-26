;;; tests/test-packet.scm — HEGL packet framing tests

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (hegel packet)
             (hegel crc32)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports)
             (srfi srfi-11)
             (srfi srfi-64))

(test-begin "packet")

;;;; ── Helpers ──────────────────────────────────────────────────────────────────

(define (packet->bytevector packet)
  "Serialize PACKET to a bytevector via a bytevector output port."
  (let-values (((port get-bv) (open-bytevector-output-port)))
    (write-hegl-packet! port packet)
    (get-bv)))

(define (bytevector->packet bv)
  "Deserialize a HEGL packet from bytevector BV."
  (read-hegl-packet! (open-bytevector-input-port bv)))

;;;; ── Round-trip tests ─────────────────────────────────────────────────────────

(test-group "round-trip"
  ;; Simple payload
  (let* ((payload (string->utf8 "hello"))
         (pkt (make-hegl-packet 0 1 payload))
         (wire (packet->bytevector pkt))
         (pkt2 (bytevector->packet wire)))
    (test-equal "channel-id preserved"
      0 (hegl-packet-channel-id pkt2))
    (test-equal "message-id preserved"
      1 (hegl-packet-message-id pkt2))
    (test-equal "payload preserved"
      payload (hegl-packet-payload pkt2))
    (test-assert "not a reply"
      (not (hegl-packet-is-reply? pkt2))))

  ;; Reply packet (bit 31 set)
  (let* ((payload (string->utf8 "ok"))
         (msg-id (logior 1 %reply-bit))
         (pkt (make-hegl-packet 0 msg-id payload))
         (wire (packet->bytevector pkt))
         (pkt2 (bytevector->packet wire)))
    (test-assert "is a reply"
      (hegl-packet-is-reply? pkt2))
    (test-equal "message-id with reply bit"
      msg-id (hegl-packet-message-id pkt2)))

  ;; Empty payload
  (let* ((pkt (make-hegl-packet 0 1 (make-bytevector 0)))
         (wire (packet->bytevector pkt))
         (pkt2 (bytevector->packet wire)))
    (test-equal "empty payload round-trips"
      0 (bytevector-length (hegl-packet-payload pkt2))))

  ;; Large-ish payload (1024 bytes)
  (let* ((payload (make-bytevector 1024 #xAB))
         (pkt (make-hegl-packet 3 42 payload))
         (wire (packet->bytevector pkt))
         (pkt2 (bytevector->packet wire)))
    (test-equal "large payload preserved"
      payload (hegl-packet-payload pkt2))
    (test-equal "channel 3"
      3 (hegl-packet-channel-id pkt2))))

;;;; ── Wire format structure ────────────────────────────────────────────────────

(test-group "wire-format"
  (let* ((pkt (make-hegl-packet 0 1 (string->utf8 "test")))
         (wire (packet->bytevector pkt)))
    ;; Total size: 20 header + 4 payload + 1 terminator = 25
    (test-equal "wire size"
      25 (bytevector-length wire))
    ;; First 4 bytes: magic
    (test-equal "magic bytes"
      #x4845474C
      (bytevector-u32-ref wire 0 (endianness big)))
    ;; Last byte: terminator
    (test-equal "terminator"
      #x0A
      (bytevector-u8-ref wire (- (bytevector-length wire) 1)))
    ;; Payload length field at offset 16
    (test-equal "payload-length field"
      4
      (bytevector-u32-ref wire 16 (endianness big)))))

;;;; ── Validation tests ─────────────────────────────────────────────────────────

(test-group "validation"
  ;; Bad magic
  (let* ((pkt (make-hegl-packet 0 1 (string->utf8 "x")))
         (wire (packet->bytevector pkt)))
    ;; Corrupt magic
    (bytevector-u32-set! wire 0 #xDEADBEEF (endianness big))
    (test-error "bad magic raises"
      #t
      (bytevector->packet wire)))

  ;; Bad CRC32
  (let* ((pkt (make-hegl-packet 0 1 (string->utf8 "y")))
         (wire (packet->bytevector pkt)))
    ;; Corrupt one payload byte
    (bytevector-u8-set! wire 20 (logxor (bytevector-u8-ref wire 20) #xFF))
    (test-error "bad crc raises"
      #t
      (bytevector->packet wire)))

  ;; Bad terminator
  (let* ((pkt (make-hegl-packet 0 1 (string->utf8 "z")))
         (wire (packet->bytevector pkt)))
    ;; Corrupt terminator (last byte)
    (bytevector-u8-set! wire (- (bytevector-length wire) 1) #xFF)
    (test-error "bad terminator raises"
      #t
      (bytevector->packet wire))))

;;;; ── Constants ────────────────────────────────────────────────────────────────

(test-group "constants"
  (test-equal "reply-bit is bit 31"
    (expt 2 31) %reply-bit)
  (test-equal "channel-close-id"
    (- (expt 2 31) 1) %channel-close-id)
  (test-equal "channel-close-payload is 0xFE"
    #xFE (bytevector-u8-ref %channel-close-payload 0)))

(test-end "packet")
