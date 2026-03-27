;;; tests/test-mux.scm — Connection multiplexer tests (C-011)

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (hegel mux)
             (hegel channel)
             (hegel packet)
             (hegel cbor)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports)
             (srfi srfi-11)
             (srfi srfi-64))

(test-begin "mux")

;;;; ── Helpers ────────────────────────────────────────────────────────────────

(define (write-packets-to-bytevector packets)
  "Serialize a list of HEGL packets into a single bytevector."
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (for-each (lambda (pkt) (write-hegl-packet! out-port pkt))
              packets)
    (get-bv)))

(define (make-test-mux wire-bv)
  "Create a mux whose in-port reads from WIRE-BV and out-port captures writes."
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let ((in-port (open-bytevector-input-port wire-bv)))
      (values (make-connection-mux in-port out-port) get-bv))))

;;;; ── Basic construction ─────────────────────────────────────────────────────

(test-group "mux-construction"
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((in-port (open-bytevector-input-port (make-bytevector 0)))
           (mux (make-connection-mux in-port out-port)))
      (test-assert "connection-mux? predicate"
        (connection-mux? mux))
      (test-assert "in-port accessor"
        (eq? in-port (connection-mux-in-port mux)))
      (test-assert "out-port accessor"
        (eq? out-port (connection-mux-out-port mux))))))

;;;; ── mux-write-packet! pass-through ─────────────────────────────────────────

(test-group "mux-write-passthrough"
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((in-port (open-bytevector-input-port (make-bytevector 0)))
           (mux     (make-connection-mux in-port out-port))
           (payload (string->utf8 "hello"))
           (packet  (make-hegl-packet 0 1 payload)))
      (mux-write-packet! mux packet)
      ;; Verify it was written correctly by reading it back
      (let* ((wire (get-bv))
             (read-back (read-hegl-packet! (open-bytevector-input-port wire))))
        (test-equal "written packet channel-id" 0 (hegl-packet-channel-id read-back))
        (test-equal "written packet message-id" 1 (hegl-packet-message-id read-back))
        (test-equal "written packet payload" payload (hegl-packet-payload read-back))))))

;;;; ── Core demux: interleaved packets ────────────────────────────────────────

(test-group "demux-interleaved"
  ;; Simulate: channel-1 packet arrives first, then channel-0 packet.
  ;; Reading for channel 0 should skip (buffer) channel 1's packet and return
  ;; channel 0's packet. Then reading for channel 1 should return from buffer.
  (let* ((payload-ch1 (string->utf8 "for-channel-1"))
         (payload-ch0 (string->utf8 "for-channel-0"))
         (pkt-ch1 (make-hegl-packet 1 (logior 1 %reply-bit) payload-ch1))
         (pkt-ch0 (make-hegl-packet 0 (logior 1 %reply-bit) payload-ch0))
         (wire-bv (write-packets-to-bytevector (list pkt-ch1 pkt-ch0))))
    (let-values (((mux get-bv) (make-test-mux wire-bv)))
      ;; Read for channel 0: should skip channel 1 packet and return channel 0
      (let ((result-ch0 (mux-read-for-channel! mux 0)))
        (test-equal "demux returns channel 0 packet"
          0 (hegl-packet-channel-id result-ch0))
        (test-equal "demux channel 0 payload"
          payload-ch0 (hegl-packet-payload result-ch0)))

      ;; Read for channel 1: should return the buffered packet
      (let ((result-ch1 (mux-read-for-channel! mux 1)))
        (test-equal "buffered channel 1 packet returned"
          1 (hegl-packet-channel-id result-ch1))
        (test-equal "buffered channel 1 payload"
          payload-ch1 (hegl-packet-payload result-ch1))))))

;;;; ── Multiple packets per channel (FIFO ordering) ───────────────────────────

(test-group "demux-fifo-ordering"
  ;; Write: ch0-pkt1, ch1-pkt1, ch0-pkt2, ch1-pkt2
  ;; Reading ch1 twice should yield ch1-pkt1 then ch1-pkt2 (FIFO).
  (let* ((p0a (make-hegl-packet 0 (logior 1 %reply-bit) (string->utf8 "ch0-first")))
         (p1a (make-hegl-packet 1 (logior 1 %reply-bit) (string->utf8 "ch1-first")))
         (p0b (make-hegl-packet 0 (logior 2 %reply-bit) (string->utf8 "ch0-second")))
         (p1b (make-hegl-packet 1 (logior 2 %reply-bit) (string->utf8 "ch1-second")))
         (wire-bv (write-packets-to-bytevector (list p0a p1a p0b p1b))))
    (let-values (((mux get-bv) (make-test-mux wire-bv)))
      ;; Read all of channel 1 first (forces buffering of channel 0 packets)
      (let ((r1a (mux-read-for-channel! mux 1)))
        (test-equal "ch1 first packet payload"
          (string->utf8 "ch1-first") (hegl-packet-payload r1a)))
      (let ((r1b (mux-read-for-channel! mux 1)))
        (test-equal "ch1 second packet payload"
          (string->utf8 "ch1-second") (hegl-packet-payload r1b)))

      ;; Now read channel 0 — both should be buffered already
      (let ((r0a (mux-read-for-channel! mux 0)))
        (test-equal "ch0 first packet payload (from buffer)"
          (string->utf8 "ch0-first") (hegl-packet-payload r0a)))
      (let ((r0b (mux-read-for-channel! mux 0)))
        (test-equal "ch0 second packet payload (from buffer)"
          (string->utf8 "ch0-second") (hegl-packet-payload r0b))))))

;;;; ── Three channels interleaved ─────────────────────────────────────────────

(test-group "demux-three-channels"
  ;; Channels 0, 3, 5 interleaved.
  (let* ((p5  (make-hegl-packet 5 (logior 1 %reply-bit) (string->utf8 "five")))
         (p0  (make-hegl-packet 0 (logior 1 %reply-bit) (string->utf8 "zero")))
         (p3  (make-hegl-packet 3 (logior 1 %reply-bit) (string->utf8 "three")))
         (wire-bv (write-packets-to-bytevector (list p5 p0 p3))))
    (let-values (((mux get-bv) (make-test-mux wire-bv)))
      ;; Read channel 3 first — must buffer 5 and 0
      (let ((r3 (mux-read-for-channel! mux 3)))
        (test-equal "channel 3 payload" (string->utf8 "three")
          (hegl-packet-payload r3)))
      ;; Now 5 and 0 are buffered
      (let ((r0 (mux-read-for-channel! mux 0)))
        (test-equal "channel 0 payload (buffered)" (string->utf8 "zero")
          (hegl-packet-payload r0)))
      (let ((r5 (mux-read-for-channel! mux 5)))
        (test-equal "channel 5 payload (buffered)" (string->utf8 "five")
          (hegl-packet-payload r5))))))

;;;; ── Non-reply (request) packets are also demuxed ───────────────────────────

(test-group "demux-request-packets"
  ;; The server can send request packets (events like test_case) to the client.
  ;; These do NOT have the reply bit set. The mux must handle them.
  (let* ((request-pkt (make-hegl-packet 2 42 (string->utf8 "event-data")))
         (reply-pkt   (make-hegl-packet 0 (logior 1 %reply-bit) (string->utf8 "reply")))
         (wire-bv (write-packets-to-bytevector (list request-pkt reply-pkt))))
    (let-values (((mux get-bv) (make-test-mux wire-bv)))
      ;; Read for channel 0 — should buffer the channel 2 request
      (let ((r0 (mux-read-for-channel! mux 0)))
        (test-equal "got channel 0 reply" 0 (hegl-packet-channel-id r0))
        (test-assert "channel 0 is reply" (hegl-packet-is-reply? r0)))
      ;; Read for channel 2 — should return the buffered request
      (let ((r2 (mux-read-for-channel! mux 2)))
        (test-equal "got channel 2 request" 2 (hegl-packet-channel-id r2))
        (test-assert "channel 2 is not reply" (not (hegl-packet-is-reply? r2)))
        (test-equal "channel 2 payload" (string->utf8 "event-data")
          (hegl-packet-payload r2))))))

;;;; ── Muxed channel integration ──────────────────────────────────────────────

(test-group "muxed-channel-send-raw"
  ;; Verify that make-muxed-channel + channel-send-raw! writes through the mux
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((in-port (open-bytevector-input-port (make-bytevector 0)))
           (mux     (make-connection-mux in-port out-port))
           (channel (make-muxed-channel 0 mux))
           (payload (string->utf8 "muxed-send")))
      (test-assert "muxed channel has mux" (hegel-channel-mux channel))
      (let ((msg-id (channel-send-raw! channel payload)))
        (test-equal "msg-id is 1" 1 msg-id)
        ;; Verify the packet was written
        (let* ((wire (get-bv))
               (pkt (read-hegl-packet! (open-bytevector-input-port wire))))
          (test-equal "muxed send channel-id" 0 (hegl-packet-channel-id pkt))
          (test-equal "muxed send message-id" 1 (hegl-packet-message-id pkt))
          (test-equal "muxed send payload" payload (hegl-packet-payload pkt)))))))

(test-group "muxed-channel-recv-raw"
  ;; Verify that make-muxed-channel + channel-recv-raw! reads through the mux,
  ;; correctly demuxing interleaved traffic.
  (let* ((reply-ch0 (make-hegl-packet 0 (logior 1 %reply-bit) (string->utf8 "ch0-reply")))
         (reply-ch3 (make-hegl-packet 3 (logior 1 %reply-bit) (string->utf8 "ch3-reply")))
         ;; Wire order: ch3 first, then ch0
         (wire-bv (write-packets-to-bytevector (list reply-ch3 reply-ch0))))
    (let-values (((out-port get-bv) (open-bytevector-output-port)))
      (let* ((in-port (open-bytevector-input-port wire-bv))
             (mux     (make-connection-mux in-port out-port))
             (ch0     (make-muxed-channel 0 mux))
             (ch3     (make-muxed-channel 3 mux)))
        ;; Read ch0 — must skip ch3's packet
        (let ((payload (channel-recv-raw! ch0 1)))
          (test-equal "muxed recv ch0 payload"
            (string->utf8 "ch0-reply") payload))
        ;; Read ch3 — from buffer
        (let ((payload (channel-recv-raw! ch3 1)))
          (test-equal "muxed recv ch3 payload (buffered)"
            (string->utf8 "ch3-reply") payload))))))

;;;; ── Direct channels are unaffected ─────────────────────────────────────────

(test-group "direct-channel-unchanged"
  ;; Ensure make-hegel-channel still works as before (mux is #f)
  (let-values (((out-port get-bv) (open-bytevector-output-port)))
    (let* ((dummy-in (open-bytevector-input-port (make-bytevector 0)))
           (channel  (make-hegel-channel 0 dummy-in out-port)))
      (test-assert "direct channel has no mux" (not (hegel-channel-mux channel)))
      (let ((msg-id (channel-send-raw! channel (string->utf8 "direct"))))
        (test-equal "direct send returns msg-id 1" 1 msg-id)
        (let* ((wire (get-bv))
               (pkt (read-hegl-packet! (open-bytevector-input-port wire))))
          (test-equal "direct packet channel-id" 0 (hegl-packet-channel-id pkt))
          (test-equal "direct packet payload"
            (string->utf8 "direct") (hegl-packet-payload pkt)))))))

(test-end "mux")
