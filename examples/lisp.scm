;;; examples/lisp.scm — Minimal Lisp evaluator property tests
;;;
;;; Inspired by page 13 of the LISP 1.5 Programmer's Manual: the
;;; eval/apply core. We implement a tiny evaluator and test its
;;; algebraic properties with Hegel.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel)
             (srfi srfi-1))

;;;; ── Minimal Lisp Evaluator ───────────────────────────────────────────────
;;
;; Supports: integers, symbols (variable lookup), quote, if, lambda, +, -, *, =
;; Environment is an alist of (symbol . value) pairs.

(define (mini-eval expr env)
  (cond
   ;; Self-evaluating: numbers and booleans
   ((number? expr) expr)
   ((boolean? expr) expr)
   ;; Variable lookup
   ((symbol? expr)
    (let ((binding (assq expr env)))
      (if binding
          (cdr binding)
          (error "mini-eval: unbound variable" expr))))
   ;; Special forms and applications
   ((pair? expr)
    (case (car expr)
      ((quote) (cadr expr))
      ((if)
       (if (mini-eval (cadr expr) env)
           (mini-eval (caddr expr) env)
           (mini-eval (cadddr expr) env)))
      ((lambda)
       ;; Return a closure: (closure params body env)
       (list 'closure (cadr expr) (caddr expr) env))
      (else
       ;; Application
       (let ((proc (mini-eval (car expr) env))
             (args (map (lambda (a) (mini-eval a env)) (cdr expr))))
         (mini-apply proc args)))))
   (else (error "mini-eval: unknown expression" expr))))

(define (mini-apply proc args)
  (cond
   ;; Built-in primitives
   ((eq? proc 'prim-add) (apply + args))
   ((eq? proc 'prim-sub) (apply - args))
   ((eq? proc 'prim-mul) (apply * args))
   ((eq? proc 'prim-eq)  (apply = args))
   ;; User-defined closure
   ((and (pair? proc) (eq? (car proc) 'closure))
    (let* ((params (cadr proc))
           (body   (caddr proc))
           (cenv   (cadddr proc))
           (new-env (append (map cons params args) cenv)))
      (mini-eval body new-env)))
   (else (error "mini-apply: not a procedure" proc))))

;; Standard environment with primitives
(define *base-env*
  (list (cons '+ 'prim-add)
        (cons '- 'prim-sub)
        (cons '* 'prim-mul)
        (cons '= 'prim-eq)))

;;;; ── Property Tests ───────────────────────────────────────────────────────

(define-hegel-test (test-self-evaluating tc #:test-cases 200)
  "Numbers evaluate to themselves."
  (let* ((n (tc-draw tc (integers #:min-value -10000 #:max-value 10000))))
    (unless (= (mini-eval n *base-env*) n)
      (error "number not self-evaluating" n))))

(define-hegel-test (test-quote-returns-datum tc #:test-cases 200)
  "(quote x) returns x for any integer x."
  (let* ((n (tc-draw tc (integers #:min-value -10000 #:max-value 10000))))
    (unless (equal? (mini-eval (list 'quote n) *base-env*) n)
      (error "quote did not return datum" n))))

(define-hegel-test (test-addition-commutative tc #:test-cases 200)
  "(+ a b) = (+ b a) in our mini-evaluator."
  (let* ((a (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (b (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (env (append (list (cons 'a a) (cons 'b b)) *base-env*)))
    (unless (= (mini-eval '(+ a b) env)
               (mini-eval '(+ b a) env))
      (error "addition not commutative in mini-eval" a b))))

(define-hegel-test (test-multiplication-distributes tc #:test-cases 200)
  "a * (b + c) = a*b + a*c in our mini-evaluator."
  (let* ((a (tc-draw tc (integers #:min-value -100 #:max-value 100)))
         (b (tc-draw tc (integers #:min-value -100 #:max-value 100)))
         (c (tc-draw tc (integers #:min-value -100 #:max-value 100)))
         (env (append (list (cons 'a a) (cons 'b b) (cons 'c c)) *base-env*)))
    (unless (= (mini-eval '(* a (+ b c)) env)
               (mini-eval '(+ (* a b) (* a c)) env))
      (error "distributive law failed" a b c))))

(define-hegel-test (test-if-selects-branch tc #:test-cases 200)
  "(if #t a b) = a and (if #f a b) = b"
  (let* ((a (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (b (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (env (append (list (cons 'a a) (cons 'b b)) *base-env*)))
    (unless (= (mini-eval '(if #t a b) env) a)
      (error "if #t did not select then-branch" a b))
    (unless (= (mini-eval '(if #f a b) env) b)
      (error "if #f did not select else-branch" a b))))

(define-hegel-test (test-lambda-identity tc #:test-cases 200)
  "((lambda (x) x) n) = n — identity function."
  (let* ((n (tc-draw tc (integers #:min-value -10000 #:max-value 10000))))
    (unless (= (mini-eval (list (list 'lambda '(x) 'x) n) *base-env*) n)
      (error "identity lambda failed" n))))

(define-hegel-test (test-lambda-constant tc #:test-cases 200)
  "((lambda (x) 42) n) = 42 — constant function."
  (let* ((n (tc-draw tc (integers #:min-value -10000 #:max-value 10000))))
    (unless (= (mini-eval (list (list 'lambda '(x) 42) n) *base-env*) 42)
      (error "constant lambda failed" n))))

(define-hegel-test (test-nested-lambda tc #:test-cases 200)
  "((lambda (x) ((lambda (y) (+ x y)) 10)) n) = n + 10 — closure captures env."
  (let* ((n (tc-draw tc (integers #:min-value -1000 #:max-value 1000)))
         (expr '(lambda (x) ((lambda (y) (+ x y)) 10)))
         (result (mini-eval (list expr n) *base-env*)))
    (unless (= result (+ n 10))
      (error "nested lambda / closure failed" n result))))

;;; ── Run ────────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%LISP 1.5 evaluator: ~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
