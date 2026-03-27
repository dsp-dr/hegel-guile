;;; tools/stdio-probe.scm — Probe hegel-core via --stdio mode
;;; This avoids socket setup complexity and tests the wire protocol directly.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel packet) (hegel channel) (hegel protocol) (hegel cbor)
             (rnrs bytevectors) (ice-9 binary-ports) (ice-9 format)
             (ice-9 popen))

(define hegel-path
  (or (getenv "HEGEL_CMD")
      (string-append (or (getenv "HOME") "") "/.local/bin/hegel")))

(define (decode-payload pkt)
  (catch #t
    (lambda () (cbor-decode (hegl-packet-payload pkt)))
    (lambda _ (hegl-packet-payload pkt))))

(define (log . args)
  (apply format (current-error-port) args)
  (force-output (current-error-port)))

;; Spawn hegel --stdio
(let ((pipe (open-input-output-pipe
              (string-append hegel-path " --stdio --verbosity quiet"))))
  (setvbuf pipe 'none)

  (let ((ctl (make-hegel-channel 0 pipe pipe)))

    ;; 1. Handshake
    (log "--- handshake ---~%")
    (let* ((mid (channel-send-raw! ctl %handshake-string))
           (reply (channel-recv-raw! ctl mid)))
      (log "server: ~a~%" (utf8->string reply))

      ;; 2. run_test (1 test case)
      (log "~%--- run_test ---~%")
      (let* ((tc-chid 1)
             (run-msg (list (cons "command" "run_test")
                            (cons "channel_id" tc-chid)
                            (cons "test_cases" 1))))
        (channel-send-cbor! ctl run-msg)
        (log "TX: ~s~%" run-msg)

        ;; 3. Read packet stream
        (log "~%--- packet stream ---~%")
        (let loop ((n 0))
          (when (< n 20)
            (let* ((pkt (read-hegl-packet! pipe))
                   (ch  (hegl-packet-channel-id pkt))
                   (mid (hegl-packet-message-id pkt))
                   (rpl (hegl-packet-is-reply? pkt))
                   (pl  (decode-payload pkt)))

              (log "[~2d] ch=~a mid=~a reply=~a ~s~%" n ch mid rpl pl)

              (cond
               ;; Reply to run_test on control channel
               ((and rpl (= ch 0))
                (log "     run_test ack~%")
                (loop (+ n 1)))

               ;; test_case event
               ((and (not rpl) (list? pl) (assoc "event" pl)
                     (equal? (cdr (assoc "event" pl)) "test_case"))
                (let ((tc-ch (cdr (assoc "channel_id" pl))))
                  (log "     test_case on tc-ch=~a~%" tc-ch)
                  ;; Ack the event
                  (write-hegl-packet! pipe
                    (make-hegl-packet ch (logior mid %reply-bit)
                                      (cbor-encode (list (cons "result" 'null)))))
                  ;; Generate
                  (write-hegl-packet! pipe
                    (make-hegl-packet tc-ch 1
                      (cbor-encode (list (cons "command" "generate")
                                         (cons "schema"
                                               (list (cons "type" "integer")))))))
                  (let* ((gen-pkt (read-hegl-packet! pipe))
                         (val (decode-payload gen-pkt)))
                    (log "     generated: ~s~%" val))
                  ;; mark_complete
                  (write-hegl-packet! pipe
                    (make-hegl-packet tc-ch 2
                      (cbor-encode (list (cons "command" "mark_complete")
                                         (cons "status" "VALID")))))
                  (let* ((mc-pkt (read-hegl-packet! pipe))
                         (mc-val (decode-payload mc-pkt)))
                    (log "     mark_complete ack: ~s~%" mc-val))
                  (loop (+ n 1))))

               ;; test_done event
               ((and (not rpl) (list? pl) (assoc "event" pl)
                     (equal? (cdr (assoc "event" pl)) "test_done"))
                (log "     TEST DONE~%")
                (log "     results: ~s~%"
                     (cdr (assoc "results" pl)))
                ;; Ack
                (write-hegl-packet! pipe
                  (make-hegl-packet ch (logior mid %reply-bit)
                                    (cbor-encode (list (cons "result" 'null)))))
                (log "~%=== PROBE COMPLETE ===~%"))

               (else
                (log "     (unhandled)~%")
                ;; Ack if request
                (unless rpl
                  (write-hegl-packet! pipe
                    (make-hegl-packet ch (logior mid %reply-bit)
                                      (cbor-encode (list (cons "result" 'null))))))
                (loop (+ n 1)))))))

        (close-pipe pipe)))))
