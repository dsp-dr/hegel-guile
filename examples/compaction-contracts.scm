;;; examples/compaction-contracts.scm — compaction invariant contracts
;;;
;;; Origin: ported from guile-sage src/sage/compaction.scm
;;; (commit dsp-dr/guile-sage@571286a, tests/test-compaction-deep.scm)
;;;
;;; Uses Hypothesis-backed shrinking via hegel-core to find the
;;; SMALLEST message history that violates a compaction invariant.
;;; This is much stronger than the ad-hoc PBT in sage's test suite
;;; because Hypothesis can minimize counterexamples.
;;;
;;; To run (requires hegel-core server running on stdio):
;;;   cd ~/ghq/github.com/dsp-dr/hegel-guile
;;;   guile3 -L src -L ~/ghq/github.com/dsp-dr/guile-sage/src \
;;;          examples/compaction-contracts.scm
;;;
;;; The -L flag adds sage's src to the load path so we can import
;;; (sage compaction) directly — no copies needed.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

;; Add guile-sage's src to the load path
;; Adjust this path if your guile-sage checkout is elsewhere
(let ((sage-src (or (getenv "SAGE_SRC")
                    (string-append (getenv "HOME")
                                  "/ghq/github.com/dsp-dr/guile-sage/src"))))
  (add-to-load-path sage-src))

(use-modules (hegel)
             (sage compaction)
             (sage session)
             (srfi srfi-1))

;;; ============================================================
;;; Message generators
;;; ============================================================

(define (draw-role tc)
  "Draw a message role."
  (let ((i (modulo (tc-draw tc (integers #:min-value 0 #:max-value 2)) 3)))
    (case i
      ((0) "user")
      ((1) "assistant")
      ((2) "system"))))

(define (draw-message tc)
  "Draw a realistic-shaped message alist."
  (let* ((role (draw-role tc))
         (content-len (tc-draw tc (integers #:min-value 1 #:max-value 200)))
         (content (tc-draw tc (text)))
         ;; Truncate to desired length
         (trimmed (if (> (string-length content) content-len)
                      (substring content 0 content-len)
                      content))
         (tokens (max 1 (quotient (string-length trimmed) 4))))
    `(("role" . ,role)
      ("content" . ,trimmed)
      ("tokens" . ,tokens))))

(define (draw-message-history tc min-msgs max-msgs)
  "Draw a list of messages with at least one system and one user."
  (let* ((n (tc-draw tc (integers #:min-value min-msgs #:max-value max-msgs)))
         (msgs (map (lambda (_) (draw-message tc)) (iota n)))
         ;; Ensure at least one system and one user
         (has-system? (any (lambda (m) (equal? (assoc-ref m "role") "system")) msgs))
         (has-user? (any (lambda (m) (equal? (assoc-ref m "role") "user")) msgs))
         (fixed (append
                 (if has-system? '() (list `(("role" . "system")
                                             ("content" . "You are an agent.")
                                             ("tokens" . 5))))
                 (if has-user? '() (list `(("role" . "user")
                                           ("content" . "Hello")
                                           ("tokens" . 2))))
                 msgs)))
    fixed))

;;; ============================================================
;;; Contract 1: compact-truncate preserves system messages
;;; ============================================================

(define-hegel-test (test-truncate-preserves-system tc #:test-cases 200)
  (let* ((history (draw-message-history tc 5 30))
         (keep (tc-draw tc (integers #:min-value 2 #:max-value 10)))
         (compacted (compact-truncate history #:keep keep))
         (orig-sys (filter (lambda (m) (equal? (assoc-ref m "role") "system")) history))
         (comp-sys (filter (lambda (m) (equal? (assoc-ref m "role") "system")) compacted)))
    (unless (>= (length comp-sys) (length orig-sys))
      (error "truncate lost system messages" (length orig-sys) (length comp-sys)))))

;;; ============================================================
;;; Contract 2: compact-token-limit respects the budget
;;; ============================================================

(define-hegel-test (test-token-limit-respects-budget tc #:test-cases 200)
  (let* ((history (draw-message-history tc 5 30))
         (budget (tc-draw tc (integers #:min-value 50 #:max-value 500)))
         (compacted (compact-token-limit history #:max-tokens budget))
         (total (fold + 0 (map message-tokens compacted))))
    ;; Allow 20% slack for rounding/estimation
    (unless (<= total (* budget 1.2))
      (error "token-limit exceeded budget" budget total))))

;;; ============================================================
;;; Contract 3: compact-auto reduces message count
;;; ============================================================

(define-hegel-test (test-auto-reduces-messages tc #:test-cases 200)
  (let* ((history (draw-message-history tc 10 40))
         (target (tc-draw tc (integers #:min-value 50 #:max-value 300)))
         (compacted (compact-auto history #:target-tokens target)))
    (unless (<= (length compacted) (length history))
      (error "auto should not increase message count"
             (length history) (length compacted)))))

;;; ============================================================
;;; Contract 4: all strategies produce valid message alists
;;; ============================================================

(define-hegel-test (test-all-strategies-valid-output tc #:test-cases 300)
  (let* ((history (draw-message-history tc 5 20))
         (strategy-idx (modulo (tc-draw tc (integers #:min-value 0 #:max-value 4)) 5))
         (compacted (case strategy-idx
                      ((0) (compact-truncate history #:keep 5))
                      ((1) (compact-token-limit history #:max-tokens 200))
                      ((2) (compact-importance history #:keep 5))
                      ((3) (compact-intent history #:max-tokens 200))
                      ((4) (compact-auto history #:target-tokens 200)))))
    ;; Every element must be a valid message alist
    (for-each
     (lambda (m)
       (unless (and (pair? m)
                    (string? (assoc-ref m "role"))
                    (string? (assoc-ref m "content")))
         (error "invalid message in compacted output" m)))
     compacted)))

;;; ============================================================
;;; Contract 5: compaction-score is in [0, 100]
;;; ============================================================

(define-hegel-test (test-compaction-score-range tc #:test-cases 200)
  (let* ((ratio (/ (tc-draw tc (integers #:min-value 0 #:max-value 100)) 100.0))
         (retention (/ (tc-draw tc (integers #:min-value 0 #:max-value 100)) 100.0))
         (compression (/ (tc-draw tc (integers #:min-value 0 #:max-value 100)) 100.0))
         (score (compaction-score ratio retention compression)))
    (unless (and (>= score 0) (<= score 100))
      (error "score out of range" score ratio retention compression))))

;;; ============================================================
;;; Contract 6: message-tokens is always positive
;;; ============================================================

(define-hegel-test (test-message-tokens-positive tc #:test-cases 500)
  (let ((msg (draw-message tc)))
    (unless (> (message-tokens msg) 0)
      (error "message-tokens should be positive" msg (message-tokens msg)))))

;;; ============================================================
;;; Run
;;; ============================================================

(let ((failures (run-hegel-tests!)))
  (format #t "~%~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
