;;; examples/sicp.scm — SICP-inspired property tests
;;;
;;; Classic examples from Structure and Interpretation of Computer Programs
;;; that benefit from property-based testing: interval arithmetic (§2.1.4),
;;; symbolic differentiation (§2.3.2), and rational number arithmetic (§2.1.1).

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel))

;;;; ── Interval Arithmetic (SICP §2.1.4) ────────────────────────────────────
;;
;; An interval [lo, hi] represents uncertain quantities. We test that
;; interval addition is commutative and that width is additive.

(define (make-interval lo hi) (cons lo hi))
(define (lower-bound i) (car i))
(define (upper-bound i) (cdr i))

(define (add-interval a b)
  (make-interval (+ (lower-bound a) (lower-bound b))
                 (+ (upper-bound a) (upper-bound b))))

(define (interval-width i)
  (/ (- (upper-bound i) (lower-bound i)) 2))

(define-hegel-test (test-interval-addition-commutative tc #:test-cases 200)
  "Interval addition is commutative: a + b = b + a"
  (let* ((a-lo (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (a-hi (tc-draw tc (integers #:min-value 0 #:max-value 1000)))
         (b-lo (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (b-hi (tc-draw tc (integers #:min-value 0 #:max-value 1000)))
         (a (make-interval a-lo (+ a-lo a-hi)))
         (b (make-interval b-lo (+ b-lo b-hi)))
         (ab (add-interval a b))
         (ba (add-interval b a)))
    (unless (and (= (lower-bound ab) (lower-bound ba))
                 (= (upper-bound ab) (upper-bound ba)))
      (error "interval addition not commutative" a b ab ba))))

(define-hegel-test (test-interval-width-additive tc #:test-cases 200)
  "Width of (a + b) = width(a) + width(b)"
  (let* ((a-lo (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (a-hi (tc-draw tc (integers #:min-value 0 #:max-value 1000)))
         (b-lo (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (b-hi (tc-draw tc (integers #:min-value 0 #:max-value 1000)))
         (a (make-interval a-lo (+ a-lo a-hi)))
         (b (make-interval b-lo (+ b-lo b-hi)))
         (sum (add-interval a b)))
    (unless (= (interval-width sum)
               (+ (interval-width a) (interval-width b)))
      (error "width not additive" a b))))

;;;; ── Rational Numbers (SICP §2.1.1) ───────────────────────────────────────
;;
;; Rational number arithmetic with GCD normalization. Property: addition
;; of rationals is associative after normalization.

(define (make-rat n d)
  (let ((g (gcd (abs n) (abs d)))
        (sign (if (negative? d) -1 1)))
    (cons (* sign (/ n g)) (* sign (/ d g)))))

(define (numer r) (car r))
(define (denom r) (cdr r))

(define (add-rat a b)
  (make-rat (+ (* (numer a) (denom b))
               (* (numer b) (denom a)))
            (* (denom a) (denom b))))

(define (rat-equal? a b)
  (= (* (numer a) (denom b))
     (* (numer b) (denom a))))

(define-hegel-test (test-rational-addition-associative tc #:test-cases 300)
  "(a + b) + c = a + (b + c) for rational numbers"
  (let* ((n1 (tc-draw tc (integers #:min-value -100 #:max-value 100)))
         (d1 (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (n2 (tc-draw tc (integers #:min-value -100 #:max-value 100)))
         (d2 (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (n3 (tc-draw tc (integers #:min-value -100 #:max-value 100)))
         (d3 (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (a (make-rat n1 d1))
         (b (make-rat n2 d2))
         (c (make-rat n3 d3))
         (lhs (add-rat (add-rat a b) c))
         (rhs (add-rat a (add-rat b c))))
    (unless (rat-equal? lhs rhs)
      (error "rational addition not associative" a b c lhs rhs))))

(define-hegel-test (test-rational-zero-identity tc #:test-cases 200)
  "a + 0 = a for any rational a"
  (let* ((n (tc-draw tc (integers #:min-value -100 #:max-value 100)))
         (d (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (a (make-rat n d))
         (zero (make-rat 0 1))
         (result (add-rat a zero)))
    (unless (rat-equal? result a)
      (error "zero not identity" a result))))

;;;; ── Symbolic Differentiation (SICP §2.3.2) ───────────────────────────────
;;
;; A tiny symbolic differentiator. Property: derivative of (x + c) with
;; respect to x is always 1, and derivative of a constant is always 0.

(define (variable? e) (symbol? e))
(define (same-variable? v1 v2) (and (variable? v1) (variable? v2) (eq? v1 v2)))
(define (sum? e) (and (pair? e) (eq? (car e) '+)))
(define (product? e) (and (pair? e) (eq? (car e) '*)))
(define (addend e) (cadr e))
(define (augend e) (caddr e))
(define (multiplier e) (cadr e))
(define (multiplicand e) (caddr e))

(define (make-sum a b)
  (cond ((and (number? a) (= a 0)) b)
        ((and (number? b) (= b 0)) a)
        ((and (number? a) (number? b)) (+ a b))
        (else (list '+ a b))))

(define (make-product a b)
  (cond ((or (and (number? a) (= a 0))
             (and (number? b) (= b 0))) 0)
        ((and (number? a) (= a 1)) b)
        ((and (number? b) (= b 1)) a)
        ((and (number? a) (number? b)) (* a b))
        (else (list '* a b))))

(define (deriv exp var)
  (cond ((number? exp) 0)
        ((variable? exp) (if (same-variable? exp var) 1 0))
        ((sum? exp)
         (make-sum (deriv (addend exp) var)
                   (deriv (augend exp) var)))
        ((product? exp)
         (make-sum (make-product (multiplier exp)
                                 (deriv (multiplicand exp) var))
                   (make-product (deriv (multiplier exp) var)
                                 (multiplicand exp))))
        (else (error "unknown expression type" exp))))

(define-hegel-test (test-derivative-of-x-plus-constant tc #:test-cases 200)
  "d/dx (x + c) = 1 for any constant c"
  (let* ((c (tc-draw tc (integers #:min-value -10000 #:max-value 10000)))
         (expr (list '+ 'x c))
         (result (deriv expr 'x)))
    (unless (equal? result 1)
      (error "d/dx (x + c) should be 1" c result))))

(define-hegel-test (test-derivative-of-constant tc #:test-cases 200)
  "d/dx c = 0 for any constant c"
  (let* ((c (tc-draw tc (integers #:min-value -10000 #:max-value 10000))))
    (unless (equal? (deriv c 'x) 0)
      (error "d/dx constant should be 0" c))))

(define-hegel-test (test-product-rule tc #:test-cases 200)
  "d/dx (c * x) = c"
  (let* ((c (tc-draw tc (integers #:min-value -100 #:max-value 100))))
    (unless (equal? (deriv (list '* c 'x) 'x) c)
      (error "d/dx (c * x) should be c" c (deriv (list '* c 'x) 'x)))))

;;; ── Run ────────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%SICP examples: ~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
