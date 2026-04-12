;;; examples/file-roundtrip.scm — write/read filesystem honesty cage
;;;
;;; Origin: ported from guile-sage src/sage/tools.scm:write_file +
;;; the resolve-path helper (commit dsp-dr/guile-sage@728bcc4,
;;; bd guile-ecn).
;;;
;;; The pattern: any tool that takes a "path" string and writes a
;;; file should report the ACTUAL filesystem location it wrote to,
;;; not the input path the user supplied. sage's write_file used to
;;; lie: given /tmp/foo.txt it would silently write to
;;; <workspace>/tmp/foo.txt (because (string-append workspace "/"
;;; path) double-slashed for absolute inputs and the OS normalised
;;; the //) but echo "Wrote N bytes to /tmp/foo.txt" verbatim. A
;;; downstream user who trusted the message would look in /tmp/ and
;;; find nothing. Documented in docs/UX-FINDINGS-0.6.0.md gap #1.
;;;
;;; The fix introduces resolve-path which honours absolute prefixes,
;;; and the success message echoes the resolved path. The properties
;;; below are the honesty contract: for any input, the file MUST
;;; exist where the function says it does, AND a subsequent read
;;; with the same input MUST return the bytes that were written.
;;;
;;; This generalises beyond sage. Any helper that touches the
;;; filesystem and reports the location should satisfy the same
;;; round-trip + honesty pair.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel)
             (ice-9 textual-ports))

;;; The helper under test (a minimal model of sage's resolve-path +
;;; write_file). In a real project this would be the project's
;;; actual write helper, called via the same boundary.
(define (resolve-path path workspace)
  "Map a tool-supplied path to its actual filesystem location.
   Absolute paths kept as-is, relative paths anchored to workspace."
  (cond
   ((not path) #f)
   ((string-null? path) workspace)
   ((string-prefix? "/" path) path)
   (else (string-append workspace "/" path))))

(define (write-file path content workspace)
  "Write content to the resolved location. Returns (cons resolved-path
   bytes-written) so callers can verify both AT once."
  (let ((full-path (resolve-path path workspace)))
    (call-with-output-file full-path
      (lambda (port) (display content port)))
    (cons full-path (string-length content))))

(define (read-file path workspace)
  "Read content from the resolved location."
  (let ((full-path (resolve-path path workspace)))
    (if (file-exists? full-path)
        (call-with-input-file full-path get-string-all)
        #f)))

;;; ── Property 1: write_file echoes a path that actually exists ─────────────

(define-hegel-test (test-write-file-honest-path tc #:test-cases 100)
  (let* ((basename (string-append "hegel-fr-" (number->string (current-time))
                                  "-" (number->string (tc-draw tc (integers #:min-value 1000 #:max-value 9999))) ".txt"))
         (path (string-append "/tmp/" basename))
         (content (tc-draw tc (text)))
         (result (write-file path content "/tmp"))
         (resolved (car result)))
    (unless (file-exists? resolved)
      (error "write_file echoed a path that does not exist" path resolved))
    ;; Cleanup
    (when (file-exists? resolved) (delete-file resolved))))

;;; ── Property 2: write -> read roundtrip preserves content ─────────────────

(define-hegel-test (test-file-roundtrip tc #:test-cases 100)
  (let* ((basename (string-append "hegel-fr-" (number->string (current-time))
                                  "-" (number->string (tc-draw tc (integers #:min-value 1000 #:max-value 9999))) ".txt"))
         (path (string-append "/tmp/" basename))
         (content (tc-draw tc (text)))
         (workspace "/tmp")
         (_ (write-file path content workspace))
         (read-back (read-file path workspace)))
    (unless (equal? read-back content)
      (error "write -> read roundtrip failed" content read-back))
    ;; Cleanup
    (let ((resolved (resolve-path path workspace)))
      (when (file-exists? resolved) (delete-file resolved)))))

;;; ── Property 3: byte count in write result matches actual file size ───────

(define-hegel-test (test-write-file-byte-count tc #:test-cases 100)
  (let* ((basename (string-append "hegel-fr-" (number->string (current-time))
                                  "-" (number->string (tc-draw tc (integers #:min-value 1000 #:max-value 9999))) ".txt"))
         (path (string-append "/tmp/" basename))
         ;; Use ASCII strings only so byte length == char length.
         ;; Real-world encoding tests are deferred.
         (content (let* ((n (tc-draw tc (integers #:min-value 0 #:max-value 200)))
                         (chars (map (lambda (_)
                                       (integer->char
                                        (+ 32 (modulo (tc-draw tc (integers #:min-value 0 #:max-value 94))) 95)))
                                     (iota n))))
                    (list->string chars)))
         (result (write-file path content "/tmp"))
         (resolved (car result))
         (claimed-bytes (cdr result))
         (actual-bytes (stat:size (stat resolved))))
    (unless (= claimed-bytes actual-bytes)
      (error "claimed bytes != actual file size" claimed-bytes actual-bytes))
    (when (file-exists? resolved) (delete-file resolved))))

;;; ── Property 4: relative paths land under workspace ───────────────────────

(define-hegel-test (test-relative-path-under-workspace tc #:test-cases 50)
  (let* ((basename (string-append "hegel-fr-" (number->string (current-time))
                                  "-" (number->string (tc-draw tc (integers #:min-value 1000 #:max-value 9999))) ".txt"))
         ;; Use a workspace that exists; /tmp is the safest universal choice
         (workspace "/tmp")
         (rel basename)
         (result (write-file rel "rel-content" workspace))
         (resolved (car result)))
    (unless (string-prefix? workspace resolved)
      (error "relative path must resolve under workspace" rel workspace resolved))
    (unless (file-exists? resolved)
      (error "resolved relative path must exist on disk" resolved))
    (when (file-exists? resolved) (delete-file resolved))))

;;; ── Run all ──────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
