;;; hegel/generators.scm — Generator schema combinators

(define-module (hegel generators)
  #:export (;; Primitives
            integers
            booleans
            floats
            text
            binary
            ;; Collections
            lists-of
            one-of
            ;; Combinators
            gen-filter
            gen-map
            ;; Composite helper
            define-composite))

;;;; ── Schema builders ────────────────────────────────────────────────────────

(define (integers . opts)
  "Generate integers. Keyword opts: #:min-value, #:max-value."
  (let loop ((opts opts) (schema (list (cons "type" "integers"))))
    (cond
     ((null? opts) (reverse schema))
     ((eq? (car opts) #:min-value)
      (loop (cddr opts)
            (cons (cons "min_value" (cadr opts)) schema)))
     ((eq? (car opts) #:max-value)
      (loop (cddr opts)
            (cons (cons "max_value" (cadr opts)) schema)))
     (else
      (error "integers: unknown keyword" (car opts))))))

(define (booleans)
  (list (cons "type" "booleans")))

(define (floats . opts)
  "Generate IEEE 754 doubles. Opts: #:min-value, #:max-value,
   #:allow-nan, #:allow-infinity."
  (let loop ((opts opts) (schema (list (cons "type" "floats"))))
    (cond
     ((null? opts) (reverse schema))
     ((eq? (car opts) #:min-value)
      (loop (cddr opts) (cons (cons "min_value" (cadr opts)) schema)))
     ((eq? (car opts) #:max-value)
      (loop (cddr opts) (cons (cons "max_value" (cadr opts)) schema)))
     ((eq? (car opts) #:allow-nan)
      (loop (cddr opts) (cons (cons "allow_nan" (cadr opts)) schema)))
     ((eq? (car opts) #:allow-infinity)
      (loop (cddr opts) (cons (cons "allow_infinity" (cadr opts)) schema)))
     (else (error "floats: unknown keyword" (car opts))))))

(define (text . opts)
  "Generate Unicode strings. Opts: #:min-size, #:max-size."
  (let loop ((opts opts) (schema (list (cons "type" "text"))))
    (cond
     ((null? opts) (reverse schema))
     ((eq? (car opts) #:min-size)
      (loop (cddr opts) (cons (cons "min_size" (cadr opts)) schema)))
     ((eq? (car opts) #:max-size)
      (loop (cddr opts) (cons (cons "max_size" (cadr opts)) schema)))
     (else (error "text: unknown keyword" (car opts))))))

(define (binary . opts)
  "Generate arbitrary bytevectors."
  (let loop ((opts opts) (schema (list (cons "type" "binary"))))
    (cond
     ((null? opts) (reverse schema))
     ((eq? (car opts) #:min-size)
      (loop (cddr opts) (cons (cons "min_size" (cadr opts)) schema)))
     ((eq? (car opts) #:max-size)
      (loop (cddr opts) (cons (cons "max_size" (cadr opts)) schema)))
     (else (error "binary: unknown keyword" (car opts))))))

(define (lists-of element-schema . opts)
  "Generate lists of ELEMENT-SCHEMA values. Opts: #:min-size, #:max-size."
  (let loop ((opts opts)
             (schema (list (cons "type"     "lists")
                           (cons "elements" element-schema))))
    (cond
     ((null? opts) (reverse schema))
     ((eq? (car opts) #:min-size)
      (loop (cddr opts) (cons (cons "min_size" (cadr opts)) schema)))
     ((eq? (car opts) #:max-size)
      (loop (cddr opts) (cons (cons "max_size" (cadr opts)) schema)))
     (else (error "lists-of: unknown keyword" (car opts))))))

(define (one-of . schemas)
  "Choose uniformly among SCHEMAS."
  (list (cons "type" "one_of")
        (cons "elements" schemas)))

;;;; ── Combinators ────────────────────────────────────────────────────────────
;;
;; gen-filter and gen-map are client-side: the server doesn't know about them.
;; We wrap the schema with metadata that tc-draw interprets locally.

(define (gen-filter schema pred)
  "Return a generator that only yields values satisfying PRED.
   Implemented client-side: rejected values cause tc-assume."
  (list (cons "type"      "_filter")
        (cons "_schema"   schema)
        (cons "_pred"     pred)))

(define (gen-map schema proc)
  "Return a generator that applies PROC to each drawn value."
  (list (cons "type"    "_map")
        (cons "_schema" schema)
        (cons "_proc"   proc)))

;;;; ── Composite helper ───────────────────────────────────────────────────────

(define-syntax define-composite
  (syntax-rules ()
    ((_ (name tc args ...) body ...)
     (define (name args ...)
       ;; Returns a thunk that, when called with tc, draws composite values
       (lambda (tc)
         body ...)))))
