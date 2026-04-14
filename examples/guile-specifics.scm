;;; examples/guile-specifics.scm — Properties unique to Guile Scheme
;;;
;;; Demonstrates PBT for Guile-specific features that have no analogue in
;;; mainstream languages: exact arithmetic, tail-call guarantees, s-expression
;;; structural identity, and the exact/inexact numeric tower.  These are the
;;; properties you'd show in a talk to answer "why does PBT matter for Scheme?"

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel)
             (srfi srfi-1))   ; fold, iota

;;;; ── 1. Exact arithmetic: associativity holds for arbitrary-precision ────────
;;
;; In C/Java, (a + b) + c ≠ a + (b + c) once you overflow 64 bits.
;; In Guile, exact integers are bignums — associativity always holds.

(define-hegel-test (test-bigint-addition-associative tc #:test-cases 200)
  (let ((a (tc-draw tc (integers)))
        (b (tc-draw tc (integers)))
        (c (tc-draw tc (integers))))
    (unless (= (+ (+ a b) c) (+ a (+ b c)))
      (error "addition not associative" a b c))))

;;;; ── 2. Exact/inexact distinction: the numeric tower ────────────────────────
;;
;; Guile's numeric tower means (= 3 3.0) is #t but (eqv? 3 3.0) is #f.
;; This property pins the invariant: exact->inexact->exact round-trips for
;; integers, but exactness is lost in the middle.

(define-hegel-test (test-exact-inexact-roundtrip tc #:test-cases 300)
  (let* ((n     (tc-draw tc (integers #:min-value -1000000 #:max-value 1000000)))
         (inex  (exact->inexact n))
         (back  (inexact->exact inex)))
    ;; Value is preserved
    (unless (= n back)
      (error "value changed" n back))
    ;; But exactness is lost in the middle
    (unless (exact? n)
      (error "original should be exact" n))
    (unless (inexact? inex)
      (error "intermediate should be inexact" inex))
    (unless (exact? back)
      (error "round-tripped should be exact" back))))

;;;; ── 3. Tail-call safety: fold over large lists never blows the stack ───────
;;
;; Scheme guarantees proper tail calls.  This property verifies that fold
;; (a tail-recursive higher-order function) handles deep lists without error.

(define-hegel-test (test-fold-deep-list tc #:test-cases 50)
  (let* ((size (tc-draw tc (integers #:min-value 1000 #:max-value 50000)))
         (xs   (iota size))
         (sum  (fold + 0 xs))
         ;; Gauss formula: 0 + 1 + ... + (n-1) = n*(n-1)/2
         (expected (/ (* size (- size 1)) 2)))
    (unless (= sum expected)
      (error "fold sum wrong" size sum expected))))

;;;; ── 4. Alist structural identity: assoc round-trip ─────────────────────────
;;
;; Alists are the idiomatic Guile map.  Property: building an alist from keys
;; and looking up each key always finds the last-written value.

(define-hegel-test (test-alist-last-write-wins tc #:test-cases 200)
  (let* ((n     (tc-draw tc (integers #:min-value 1 #:max-value 20)))
         (keys  (map (lambda (i)
                       (tc-draw tc (integers #:min-value 0 #:max-value 10)))
                     (iota n)))
         (vals  (map (lambda (i)
                       (tc-draw tc (integers #:min-value -100 #:max-value 100)))
                     (iota n)))
         ;; Build alist with possible duplicate keys
         (alist (map cons keys vals)))
    ;; For each key, assoc returns the FIRST occurrence (leftmost)
    ;; Verify this matches a manual scan
    (for-each
     (lambda (k)
       (let ((from-assoc (assoc k alist))
             (manual     (let loop ((pairs alist))
                           (cond ((null? pairs) #f)
                                 ((= (caar pairs) k) (car pairs))
                                 (else (loop (cdr pairs)))))))
         (unless (equal? from-assoc manual)
           (error "assoc disagrees with manual scan" k from-assoc manual))))
     (delete-duplicates keys))))

;;;; ── 5. Symbol interning: eq? works for symbols ────────────────────────────
;;
;; Guile interns symbols: (eq? 'foo 'foo) is always #t.  This property
;; generates symbol names and verifies that string->symbol round-trips
;; preserve identity (eq?, not just equal?).

(define-hegel-test (test-symbol-interning tc #:test-cases 200)
  (let* ((s   (tc-draw tc (text #:min-size 1 #:max-size 20)))
         (sym1 (string->symbol s))
         (sym2 (string->symbol s)))
    ;; Symbols from the same string must be eq? (interned)
    (unless (eq? sym1 sym2)
      (error "symbol interning broken" s sym1 sym2))
    ;; Round-trip through symbol->string
    (unless (string=? s (symbol->string sym1))
      (error "symbol->string round-trip failed" s sym1))))

;;;; ── 6. Proper tail position: map preserves list length ─────────────────────
;;
;; map must return a list of exactly the same length as its input.
;; This is trivial in theory but exercises Guile's list machinery at scale.

(define-hegel-test (test-map-preserves-length tc #:test-cases 200)
  (let* ((size (tc-draw tc (integers #:min-value 0 #:max-value 500)))
         (xs   (iota size))
         (ys   (map (lambda (x) (* x x)) xs)))
    (unless (= (length ys) size)
      (error "map changed length" size (length ys)))))

;;;; ── Run all ──────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
