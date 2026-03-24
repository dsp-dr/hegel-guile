;;; examples/basic.scm — Port of the hegel-rust quickstart examples

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel))

;;; ── Example 1: Integer addition is commutative ──────────────────────────────

(define-hegel-test (test-addition-commutative tc #:test-cases 200)
  (let ((x (tc-draw tc (integers)))
        (y (tc-draw tc (integers))))
    ;; Wrapping add to avoid overflow panics (unlike the Rust example,
    ;; Guile integers are arbitrary-precision, so this always passes).
    (unless (= (+ x y) (+ y x))
      (error "commutativity violated" x y))))

;;; ── Example 2: String parse round-trip ──────────────────────────────────────

(define-hegel-test (test-number->string-roundtrip tc #:test-cases 500)
  (let* ((n   (tc-draw tc (integers #:min-value -1000000 #:max-value 1000000)))
         (s   (number->string n))
         (n2  (string->number s)))
    (unless (= n n2)
      (error "round-trip failed" n s n2))))

;;; ── Example 3: Title case is idempotent (like the heck example) ────────────

(define (simple-title-case s)
  "Capitalise first letter of each word."
  (string-join
   (map (lambda (word)
          (if (string-null? word)
              word
              (string-append
               (string-upcase (substring word 0 1))
               (substring word 1))))
        (string-split s #\space))
   " "))

(define-hegel-test (test-title-case-idempotent tc #:test-cases 1000)
  (let* ((s     (tc-draw tc (text)))
         (once  (simple-title-case s))
         (twice (simple-title-case once)))
    (unless (string=? once twice)
      (error "title-case not idempotent" s once twice))))

;;; ── Example 4: Model-based testing of association lists ─────────────────────

(define-hegel-test (test-alist-model tc #:test-cases 300)
  ;; Model: assoc lookup on an alist matches direct search
  (let* ((keys   (tc-draw tc (lists-of (integers #:min-value 0 #:max-value 50)
                                       #:max-size 20)))
         (pairs  (map (lambda (k) (cons k (* k 2))) keys))
         (target (tc-draw tc (integers #:min-value 0 #:max-value 50)))
         (found  (assoc target pairs))
         ;; "Model": scan manually
         (model  (let loop ((ps pairs))
                   (cond ((null? ps) #f)
                         ((= (caar ps) target) (car ps))
                         (else (loop (cdr ps)))))))
    (unless (equal? found model)
      (error "alist model mismatch" target found model))))

;;; ── Run all ──────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
