;;; hegel/generators.scm — Generator schema combinators
;;;
;;; C-015: Type names match hegel-core schema.py _from_schema().
;;; "integer", "boolean", "float", "string", "binary", "list".
;;; "one_of", "const", "sampled_from" are top-level keys, not type fields.

(define-module (hegel generators)
  #:export (;; Primitives
            integers
            booleans
            floats
            text
            binary
            null-values
            ;; Collections
            lists-of
            one-of
            ;; Top-level key schemas
            sampled-from
            const-value
            ;; Combinators
            gen-filter
            gen-map
            ;; Composite helper
            define-composite))

;;;; ── Schema builders ────────────────────────────────────────────────────────

(define (integers . opts)
  "Generate integers. Keyword opts: #:min-value, #:max-value."
  (let loop ((opts opts) (schema (list (cons "type" "integer"))))
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

(define (booleans . opts)
  "Generate booleans. Keyword opts: #:p (probability of #t, 0.0-1.0)."
  (let loop ((opts opts) (schema (list (cons "type" "boolean"))))
    (cond
     ((null? opts) (reverse schema))
     ((eq? (car opts) #:p)
      (loop (cddr opts)
            (cons (cons "p" (cadr opts)) schema)))
     (else
      (error "booleans: unknown keyword" (car opts))))))

(define (floats . opts)
  "Generate IEEE 754 doubles. Opts: #:min-value, #:max-value,
   #:allow-nan, #:allow-infinity, #:width, #:exclude-min, #:exclude-max."
  (let loop ((opts opts) (schema (list (cons "type" "float"))))
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
     ((eq? (car opts) #:width)
      (loop (cddr opts) (cons (cons "width" (cadr opts)) schema)))
     ((eq? (car opts) #:exclude-min)
      (loop (cddr opts) (cons (cons "exclude_min" (cadr opts)) schema)))
     ((eq? (car opts) #:exclude-max)
      (loop (cddr opts) (cons (cons "exclude_max" (cadr opts)) schema)))
     (else (error "floats: unknown keyword" (car opts))))))

(define (text . opts)
  "Generate Unicode strings. Opts: #:min-size, #:max-size."
  (let loop ((opts opts) (schema (list (cons "type" "string"))))
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
  "Generate lists of ELEMENT-SCHEMA values. Opts: #:min-size, #:max-size, #:unique."
  (let loop ((opts opts)
             (schema (list (cons "type"     "list")
                           (cons "elements" element-schema))))
    (cond
     ((null? opts) (reverse schema))
     ((eq? (car opts) #:min-size)
      (loop (cddr opts) (cons (cons "min_size" (cadr opts)) schema)))
     ((eq? (car opts) #:max-size)
      (loop (cddr opts) (cons (cons "max_size" (cadr opts)) schema)))
     ((eq? (car opts) #:unique)
      (loop (cddr opts) (cons (cons "unique" (cadr opts)) schema)))
     (else (error "lists-of: unknown keyword" (car opts))))))

(define (one-of . schemas)
  "Choose uniformly among SCHEMAS.
   Produces a top-level 'one_of' key, not a type field.
   Wire format: {\"one_of\": [schema1, schema2, ...]}."
  (list (cons "one_of" schemas)))

(define (null-values)
  "Generate null values."
  (list (cons "type" "null")))

(define (sampled-from items)
  "Choose uniformly from the given list of ITEMS.
   Top-level key schema: {\"sampled_from\": [item1, item2, ...]}."
  (list (cons "sampled_from" items)))

(define (const-value value)
  "Always produce VALUE.
   Top-level key schema: {\"const\": value}."
  (list (cons "const" value)))

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
