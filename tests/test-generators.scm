;;; tests/test-generators.scm — Generator schema & conjecture C-003/C-015 tests

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel generators)
             (hegel cbor)
             (srfi srfi-64)
             (srfi srfi-1))

(test-begin "generators")

;;;; ── C-003: Schema keys use snake_case ────────────────────────────────────
;;
;; Conjecture: all schema keys sent to the server use snake_case.
;; We verify every generator produces alists with only snake_case string keys.

(define (snake-case? s)
  "Return #t if S matches [a-z][a-z0-9_]* (snake_case)."
  (and (string? s)
       (> (string-length s) 0)
       (let loop ((i 0))
         (if (= i (string-length s))
             #t
             (let ((c (string-ref s i)))
               (and (or (and (char>=? c #\a) (char<=? c #\z))
                        (and (char>=? c #\0) (char<=? c #\9))
                        (char=? c #\_))
                    (loop (+ i 1))))))))

(define (all-keys-snake-case? schema)
  "Return #t if all string keys in SCHEMA alist are snake_case."
  (every (lambda (pair) (snake-case? (car pair))) schema))

(test-group "C-003: snake_case keys"

  (test-assert "integers: all keys snake_case"
    (all-keys-snake-case? (integers)))

  (test-assert "integers with opts: all keys snake_case"
    (all-keys-snake-case? (integers #:min-value 0 #:max-value 100)))

  (test-assert "booleans: all keys snake_case"
    (all-keys-snake-case? (booleans)))

  (test-assert "booleans with p: all keys snake_case"
    (all-keys-snake-case? (booleans #:p 0.7)))

  (test-assert "floats: all keys snake_case"
    (all-keys-snake-case? (floats)))

  (test-assert "floats with opts: all keys snake_case"
    (all-keys-snake-case?
     (floats #:min-value -1.0 #:max-value 1.0
             #:allow-nan #f #:allow-infinity #f)))

  (test-assert "floats with width/exclude: all keys snake_case"
    (all-keys-snake-case?
     (floats #:width 32 #:exclude-min #t #:exclude-max #f)))

  (test-assert "text: all keys snake_case"
    (all-keys-snake-case? (text)))

  (test-assert "text with opts: all keys snake_case"
    (all-keys-snake-case? (text #:min-size 1 #:max-size 50)))

  (test-assert "binary: all keys snake_case"
    (all-keys-snake-case? (binary)))

  (test-assert "binary with opts: all keys snake_case"
    (all-keys-snake-case? (binary #:min-size 0 #:max-size 256)))

  (test-assert "lists-of: all keys snake_case"
    (all-keys-snake-case? (lists-of (integers))))

  (test-assert "lists-of with opts: all keys snake_case"
    (all-keys-snake-case?
     (lists-of (text) #:min-size 1 #:max-size 10)))

  (test-assert "one-of: all keys snake_case"
    (all-keys-snake-case? (one-of (integers) (text))))

  (test-assert "null-values: all keys snake_case"
    (all-keys-snake-case? (null-values)))

  (test-assert "sampled-from: all keys snake_case"
    (all-keys-snake-case? (sampled-from '("a" "b" "c"))))

  (test-assert "const-value: all keys snake_case"
    (all-keys-snake-case? (const-value 42))))

;;;; ── C-015: Type names match hegel-core ─────────────────────────────────
;;
;; Conjecture: schema type strings must match hegel-core schema.py
;; _from_schema() exactly. "integer" not "integers", etc.
;; "one_of", "sampled_from", "const" are top-level keys, not type fields.

(test-group "C-015: type names match hegel-core"

  (test-equal "integers produces type=integer"
    "integer" (cdr (assoc "type" (integers))))

  (test-equal "booleans produces type=boolean"
    "boolean" (cdr (assoc "type" (booleans))))

  (test-equal "floats produces type=float"
    "float" (cdr (assoc "type" (floats))))

  (test-equal "text produces type=string"
    "string" (cdr (assoc "type" (text))))

  (test-equal "binary produces type=binary"
    "binary" (cdr (assoc "type" (binary))))

  (test-equal "lists-of produces type=list"
    "list" (cdr (assoc "type" (lists-of (integers)))))

  (test-equal "null-values produces type=null"
    "null" (cdr (assoc "type" (null-values))))

  ;; one-of uses top-level key, not "type"
  (test-assert "one-of has no type field"
    (not (assoc "type" (one-of (integers) (text)))))

  (test-assert "one-of has one_of key"
    (assoc "one_of" (one-of (integers) (text))))

  ;; sampled-from uses top-level key
  (test-assert "sampled-from has no type field"
    (not (assoc "type" (sampled-from '("x" "y")))))

  (test-assert "sampled-from has sampled_from key"
    (assoc "sampled_from" (sampled-from '("x" "y"))))

  ;; const uses top-level key
  (test-assert "const-value has no type field"
    (not (assoc "type" (const-value 99))))

  (test-assert "const-value has const key"
    (assoc "const" (const-value 99))))

;;;; ── Schema structure tests ───────────────────────────────────────────────

(test-group "integers schema"

  (let ((s (integers)))
    (test-equal "integers type" "integer" (cdr (assoc "type" s)))
    (test-equal "integers minimal: 1 field" 1 (length s)))

  (let ((s (integers #:min-value 10 #:max-value 20)))
    (test-equal "integers type with bounds" "integer" (cdr (assoc "type" s)))
    (test-equal "integers min_value" 10 (cdr (assoc "min_value" s)))
    (test-equal "integers max_value" 20 (cdr (assoc "max_value" s)))
    (test-equal "integers bounded: 3 fields" 3 (length s))))

(test-group "booleans schema"

  (let ((s (booleans)))
    (test-equal "booleans type" "boolean" (cdr (assoc "type" s)))
    (test-equal "booleans: 1 field" 1 (length s)))

  (let ((s (booleans #:p 0.8)))
    (test-equal "booleans with p: type" "boolean" (cdr (assoc "type" s)))
    (test-equal "booleans p value" 0.8 (cdr (assoc "p" s)))
    (test-equal "booleans with p: 2 fields" 2 (length s))))

(test-group "floats schema"

  (let ((s (floats)))
    (test-equal "floats type" "float" (cdr (assoc "type" s))))

  (let ((s (floats #:allow-nan #f #:allow-infinity #f)))
    (test-equal "floats allow_nan" #f (cdr (assoc "allow_nan" s)))
    (test-equal "floats allow_infinity" #f (cdr (assoc "allow_infinity" s))))

  (let ((s (floats #:width 32 #:exclude-min #t #:exclude-max #f)))
    (test-equal "floats width" 32 (cdr (assoc "width" s)))
    (test-equal "floats exclude_min" #t (cdr (assoc "exclude_min" s)))
    (test-equal "floats exclude_max" #f (cdr (assoc "exclude_max" s)))))

(test-group "text schema"

  (let ((s (text)))
    (test-equal "text type" "string" (cdr (assoc "type" s))))

  (let ((s (text #:min-size 5 #:max-size 100)))
    (test-equal "text min_size" 5 (cdr (assoc "min_size" s)))
    (test-equal "text max_size" 100 (cdr (assoc "max_size" s)))))

(test-group "binary schema"

  (let ((s (binary)))
    (test-equal "binary type" "binary" (cdr (assoc "type" s))))

  (let ((s (binary #:min-size 0 #:max-size 1024)))
    (test-equal "binary min_size" 0 (cdr (assoc "min_size" s)))
    (test-equal "binary max_size" 1024 (cdr (assoc "max_size" s)))))

(test-group "lists-of schema"

  (let ((s (lists-of (integers))))
    (test-equal "lists-of type" "list" (cdr (assoc "type" s)))
    ;; elements should be the nested schema
    (let ((elts (cdr (assoc "elements" s))))
      (test-equal "lists-of elements type" "integer" (cdr (assoc "type" elts)))))

  (let ((s (lists-of (booleans) #:min-size 2 #:max-size 5)))
    (test-equal "lists-of with bounds: min_size" 2 (cdr (assoc "min_size" s)))
    (test-equal "lists-of with bounds: max_size" 5 (cdr (assoc "max_size" s))))

  (let ((s (lists-of (integers) #:unique #t)))
    (test-equal "lists-of with unique" #t (cdr (assoc "unique" s)))))

(test-group "one-of schema"

  (let ((s (one-of (integers) (text) (booleans))))
    (test-assert "one_of is top-level key" (assoc "one_of" s))
    (test-assert "one_of has no type field" (not (assoc "type" s)))
    (let ((alts (cdr (assoc "one_of" s))))
      (test-equal "one_of has 3 alternatives" 3 (length alts))
      (test-equal "one_of first alt is integer"
        "integer" (cdr (assoc "type" (car alts))))
      (test-equal "one_of second alt is string"
        "string" (cdr (assoc "type" (cadr alts))))
      (test-equal "one_of third alt is boolean"
        "boolean" (cdr (assoc "type" (caddr alts)))))))

(test-group "null-values schema"

  (let ((s (null-values)))
    (test-equal "null-values type" "null" (cdr (assoc "type" s)))
    (test-equal "null-values: 1 field" 1 (length s))))

(test-group "sampled-from schema"

  (let ((s (sampled-from '("red" "green" "blue"))))
    (test-assert "sampled-from has sampled_from key"
      (assoc "sampled_from" s))
    (test-assert "sampled-from has no type field"
      (not (assoc "type" s)))
    (test-equal "sampled-from items"
      '("red" "green" "blue")
      (cdr (assoc "sampled_from" s)))
    (test-equal "sampled-from: 1 field" 1 (length s))))

(test-group "const-value schema"

  (let ((s (const-value 42)))
    (test-assert "const-value has const key"
      (assoc "const" s))
    (test-assert "const-value has no type field"
      (not (assoc "type" s)))
    (test-equal "const-value value" 42 (cdr (assoc "const" s)))
    (test-equal "const-value: 1 field" 1 (length s)))

  (let ((s (const-value "hello")))
    (test-equal "const-value string" "hello" (cdr (assoc "const" s)))))

;;;; ── CBOR serialization of schemas ────────────────────────────────────────
;;
;; Schemas must survive CBOR round-trip since they're sent over the wire.

(test-group "schema CBOR round-trips"

  ;; Type-based schemas: type key survives CBOR round-trip
  (for-each
    (lambda (pair)
      (let* ((label  (car pair))
             (schema (cdr pair))
             (decoded (cbor-decode (cbor-encode schema))))
        (test-equal (string-append label ": type survives CBOR")
          (cdr (assoc "type" schema))
          (cdr (assoc "type" decoded)))))
    (list
     (cons "integer"  (integers #:min-value -100 #:max-value 100))
     (cons "boolean"  (booleans))
     (cons "float"    (floats #:min-value 0.0 #:max-value 1.0))
     (cons "string"   (text #:max-size 200))
     (cons "binary"   (binary))
     (cons "list"     (lists-of (integers)))
     (cons "null"     (null-values))))

  ;; Top-level key schemas: one_of round-trip
  (let* ((schema (one-of (integers) (booleans)))
         (decoded (cbor-decode (cbor-encode schema))))
    (test-assert "one_of key survives CBOR" (assoc "one_of" decoded))
    (test-assert "one_of has no type after CBOR" (not (assoc "type" decoded))))

  ;; sampled-from round-trip
  (let* ((schema (sampled-from '("a" "b" "c")))
         (decoded (cbor-decode (cbor-encode schema))))
    (test-assert "sampled_from key survives CBOR"
      (assoc "sampled_from" decoded)))

  ;; const round-trip
  (let* ((schema (const-value 7))
         (decoded (cbor-decode (cbor-encode schema))))
    (test-equal "const value survives CBOR"
      7 (cdr (assoc "const" decoded)))))

;;;; ── Client-side combinators ──────────────────────────────────────────────
;;
;; gen-filter and gen-map use internal "_filter"/"_map" type markers.
;; These are NOT sent to the server — tc-draw handles them locally.

(test-group "gen-filter combinator"

  (let ((s (gen-filter (integers #:min-value 0 #:max-value 100)
                       even?)))
    (test-equal "gen-filter type marker" "_filter" (cdr (assoc "type" s)))
    (let ((inner (cdr (assoc "_schema" s))))
      (test-equal "gen-filter inner schema type" "integer"
        (cdr (assoc "type" inner))))
    (test-assert "gen-filter _pred is a procedure"
      (procedure? (cdr (assoc "_pred" s))))))

(test-group "gen-map combinator"

  (let ((s (gen-map (integers) (lambda (n) (* n 2)))))
    (test-equal "gen-map type marker" "_map" (cdr (assoc "type" s)))
    (let ((inner (cdr (assoc "_schema" s))))
      (test-equal "gen-map inner schema type" "integer"
        (cdr (assoc "type" inner))))
    (test-assert "gen-map _proc is a procedure"
      (procedure? (cdr (assoc "_proc" s))))))

(test-end "generators")
