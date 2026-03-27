;;; tools/hegl-probe.scm — Manual HEGL packet inspection against live hegel-core
;;;
;;; Conjecture C9: hegel-guile's HEGL implementation matches hegel-core's
;;; wire format.
;;;
;;; Usage:
;;;   guile -L src tools/hegl-probe.scm          # bare mode
;;;   guile -L src tools/hegl-probe.scm socat     # socat proxy mode

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel crc32)
             (hegel packet)
             (hegel channel)
             (hegel protocol)
             (hegel cbor)
             (rnrs bytevectors)
             (rnrs io ports)
             (ice-9 binary-ports)
             (ice-9 format)
             (ice-9 popen)
             (ice-9 rdelim)
             (srfi srfi-11))

;;;; ── Hex dump ──────────────────────────────────────────────────────────────

(define (hex-dump bv label)
  (format #t "~a (~a bytes): " label (bytevector-length bv))
  (let ((len (bytevector-length bv)))
    (let loop ((i 0))
      (when (< i len)
        (format #t "~2,'0x " (bytevector-u8-ref bv i))
        (loop (+ i 1)))))
  (newline))

(define (show-payload bv)
  (catch #t
    (lambda ()
      (format #t "  cbor: ~s~%" (cbor-decode bv)))
    (lambda _
      (catch #t
        (lambda () (format #t "  ascii: ~s~%" (utf8->string bv)))
        (lambda _ (format #t "  (raw bytes)~%"))))))

;;;; ── Socket helpers ────────────────────────────────────────────────────────

(define (make-socket-path suffix)
  (string-append (or (getenv "TMPDIR") "/tmp")
                 "/hegel-probe-" (number->string (getpid))
                 (if suffix (string-append "." suffix) "")
                 ".sock"))

(define (wait-for-file path timeout-ms)
  (let loop ((elapsed 0))
    (cond
     ((file-exists? path) #t)
     ((>= elapsed timeout-ms)
      (error "timeout waiting for" path))
     (else
      (usleep 50000)
      (loop (+ elapsed 50))))))

(define (connect-binary path)
  (let* ((sock (socket AF_UNIX SOCK_STREAM 0)))
    (connect sock AF_UNIX path)
    (let* ((fd (fileno sock))
           (in-port  (fdopen (dup fd) "rb"))
           (out-port (fdopen (dup fd) "wb")))
      (setvbuf in-port 'none)
      (setvbuf out-port 'none)
      (values in-port out-port sock))))

(define (hegel-command)
  (or (getenv "HEGEL_SERVER_COMMAND")
      (string-append (or (getenv "HOME") "") "/.local/bin/hegel")))

;;;; ── Probe core ────────────────────────────────────────────────────────────

(define (run-probe connect-path)
  "Run the probe against a hegel-core socket at CONNECT-PATH.
Implements the actual protocol flow discovered from hegel-core 0.2.3 source:
  1. Handshake (raw bytes) on channel 0
  2. run_test command with channel_id on control channel
  3. Server sends test_case events on the test channel
  4. Client sends generate/mark_complete on server-created test_case channel
  5. Server sends test_done event when finished"
  (let-values (((in-port out-port sock) (connect-binary connect-path)))
    (let ((control (make-hegel-channel 0 in-port out-port)))

      ;; 1. Handshake
      (format #t "~%=== STEP 1: HANDSHAKE ===~%")
      (hex-dump %handshake-string "TX")
      (let* ((msg-id (channel-send-raw! control %handshake-string))
             (reply  (channel-recv-raw! control msg-id)))
        (hex-dump reply "RX")
        (let ((version (parse-server-version reply)))
          (format #t "  version: ~a~%~%" version)

          ;; 2. run_test — must include channel_id and test_cases at top level
          ;; NOTE: Packets from different channels are interleaved on the socket.
          ;; We read raw packets and dispatch manually.
          (format #t "=== STEP 2: RUN_TEST (control channel) ===~%")
          (let* ((test-channel-id (make-client-channel-id 0))  ; = 1
                 (run-msg (list (cons "command" "run_test")
                                (cons "channel_id" test-channel-id)
                                (cons "test_cases" 3))))
            ;; Send run_test as raw packet (can't use channel-send-request!
            ;; because the reply may be interleaved with events on other channels)
            (let ((msg-id (channel-send-cbor! control run-msg)))
              (format #t "TX[ch=0,mid=~a]: ~s~%" msg-id run-msg)

              ;; Now read packets until we've completed one test case.
              ;; The server will:
              ;;   1. Reply to run_test with True on channel 0
              ;;   2. Send test_case event on test channel (channel 1)
              ;;   3. Wait for generate/mark_complete on the test_case channel
              (format #t "~%=== READING PACKET STREAM ===~%")
              (let loop ((n 0) (tc-channel-id #f) (tc-msg-counter 0))
                (when (< n 20)  ; safety limit
                  (let* ((pkt (read-hegl-packet! in-port))
                         (ch  (hegl-packet-channel-id pkt))
                         (mid (hegl-packet-message-id pkt))
                         (is-reply (hegl-packet-is-reply? pkt))
                         (payload-bv (hegl-packet-payload pkt))
                         (payload (catch #t
                                    (lambda () (cbor-decode payload-bv))
                                    (lambda _ payload-bv))))
                    (format #t "  RX[ch=~a,mid=~a,reply=~a]: ~s~%"
                            ch mid is-reply payload)

                    (cond
                     ;; Reply to our run_test
                     ((and is-reply (= ch 0))
                      (format #t "    -> run_test acknowledged~%")
                      (loop (+ n 1) tc-channel-id tc-msg-counter))

                     ;; test_case event from server (request, not reply)
                     ((and (not is-reply) (assoc "event" payload))
                      (let ((event-name (cdr (assoc "event" payload))))
                        (cond
                         ((equal? event-name "test_case")
                          (let ((new-tc-ch (cdr (assoc "channel_id" payload))))
                            (format #t "    -> test_case event, tc-channel: ~a~%" new-tc-ch)
                            ;; Acknowledge the event
                            (let ((ack (make-hegl-packet
                                         ch (logior mid %reply-bit)
                                         (cbor-encode 'null))))
                              (write-hegl-packet! out-port ack))
                            (format #t "    -> acked~%")

                            ;; Send generate on the test_case channel
                            (format #t "~%=== GENERATE on tc-channel ~a ===~%"
                                    new-tc-ch)
                            (let* ((tc-mid (+ tc-msg-counter 1))
                                   (gen-msg (list (cons "command" "generate")
                                                   (cons "schema"
                                                         (list (cons "type" "integer")
                                                               (cons "min_value" -100)
                                                               (cons "max_value" 100)))))
                                   (gen-pkt (make-hegl-packet
                                              new-tc-ch tc-mid
                                              (cbor-encode gen-msg))))
                              (write-hegl-packet! out-port gen-pkt)
                              (format #t "  TX[ch=~a,mid=~a]: ~s~%" new-tc-ch tc-mid gen-msg)
                              (loop (+ n 1) new-tc-ch (+ tc-msg-counter 1)))))

                         ((equal? event-name "test_done")
                          (format #t "    -> test_done: ~s~%"
                                  (cdr (assoc "results" payload)))
                          ;; Acknowledge
                          (let ((ack (make-hegl-packet
                                       ch (logior mid %reply-bit)
                                       (cbor-encode 'null))))
                            (write-hegl-packet! out-port ack))
                          (format #t "~%=== ALL DONE ===~%"))

                         (else
                          (format #t "    -> unknown event: ~a~%" event-name)
                          (loop (+ n 1) tc-channel-id tc-msg-counter)))))

                     ;; Reply to our generate command (value from server)
                     ((and is-reply tc-channel-id (= ch tc-channel-id))
                      (format #t "    -> generated value: ~s~%" payload)

                      ;; Send mark_complete
                      (format #t "~%=== MARK_COMPLETE ===~%")
                      (let* ((mc-mid (+ tc-msg-counter 1))
                             (mc-msg (list (cons "command" "mark_complete")
                                           (cons "status" "VALID")))
                             (mc-pkt (make-hegl-packet
                                       tc-channel-id mc-mid
                                       (cbor-encode mc-msg))))
                        (write-hegl-packet! out-port mc-pkt)
                        (format #t "  TX[ch=~a,mid=~a]: ~s~%"
                                tc-channel-id mc-mid mc-msg)
                        (loop (+ n 1) tc-channel-id (+ tc-msg-counter 1))))

                     ;; Reply to mark_complete
                     ((and is-reply (equal? payload 'null))
                      (format #t "    -> mark_complete acked~%")
                      ;; Next test case or test_done will follow
                      (loop (+ n 1) #f tc-msg-counter))

                     (else
                      (format #t "    -> (unhandled, continuing)~%")
                      (loop (+ n 1) tc-channel-id tc-msg-counter)))))))))

        (format #t "~%=== PROBE COMPLETE ===~%")))

    ;; Cleanup
    (close-port in-port)
    (close-port out-port)))

;;;; ── Bare mode ─────────────────────────────────────────────────────────────

(define (probe-bare)
  (let* ((socket-path (make-socket-path #f))
         (cmd (string-append (hegel-command) " " socket-path
                             " --verbosity quiet 2>/tmp/hegel-probe.log &")))
    (format #t "--- HEGL Probe: bare mode ---~%")
    (format #t "Socket: ~a~%" socket-path)
    (system cmd)
    (wait-for-file socket-path 10000)
    (format #t "Server ready.~%")
    (catch #t
      (lambda () (run-probe socket-path))
      (lambda (tag . args)
        (format #t "~%ERROR: ~a ~s~%" tag args)
        (format #t "~%Server log:~%")
        (catch #t
          (lambda ()
            (let ((p (open-input-file "/tmp/hegel-probe.log")))
              (let loop ()
                (let ((line (read-line p)))
                  (unless (eof-object? line)
                    (format #t "  ~a~%" line)
                    (loop))))
              (close-port p)))
          (lambda _ #f))))
    (catch #t (lambda () (delete-file socket-path)) (lambda _ #f))))

;;;; ── Socat proxy mode ──────────────────────────────────────────────────────

(define (probe-socat)
  (let* ((real-path  (make-socket-path "real"))
         (proxy-path (make-socket-path #f))
         (server-cmd (string-append (hegel-command) " " real-path
                                    " --verbosity quiet 2>/tmp/hegel-probe.log &"))
         (socat-cmd  (string-append
                       "socat -x -v "
                       "UNIX-LISTEN:" proxy-path ",fork "
                       "UNIX:" real-path
                       " 2>/tmp/hegel-socat.log &")))
    (format #t "--- HEGL Probe: socat proxy mode ---~%")
    (format #t "Real socket: ~a~%" real-path)
    (format #t "Proxy socket: ~a~%" proxy-path)

    (system server-cmd)
    (wait-for-file real-path 10000)
    (format #t "Server ready.~%")

    (system socat-cmd)
    (usleep 200000)
    (format #t "socat proxy ready. Hex dump -> /tmp/hegel-socat.log~%")

    (catch #t
      (lambda () (run-probe proxy-path))
      (lambda (tag . args)
        (format #t "~%ERROR: ~a ~s~%" tag args)))

    (format #t "~%=== socat hex dump ===~%")
    (system "cat /tmp/hegel-socat.log 2>/dev/null")
    (catch #t (lambda () (delete-file real-path)) (lambda _ #f))
    (catch #t (lambda () (delete-file proxy-path)) (lambda _ #f))))

;;;; ── Entry ─────────────────────────────────────────────────────────────────

(let ((mode (if (> (length (command-line)) 1)
                (cadr (command-line))
                "bare")))
  (cond
   ((equal? mode "bare")   (probe-bare))
   ((equal? mode "socat")  (probe-socat))
   (else
    (format #t "Usage: hegl-probe.scm [bare|socat]~%"))))
