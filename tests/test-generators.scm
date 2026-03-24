;;; tests/test-generators.scm — Generator schema & conjecture C-003 tests

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

  (test-assert "floats: all keys snake_case"
    (all-keys-snake-case? (floats)))

  (test-assert "floats with opts: all keys snake_case"
    (all-keys-snake-case?
     (floats #:min-value -1.0 #:max-value 1.0
             #:allow-nan #f #:allow-infinity #f)))

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
    (all-keys-snake-case? (one-of (integers) (text)))))

;;;; ── Schema structure tests ───────────────────────────────────────────────

(test-group "integers schema"

  (let ((s (integers)))
    (test-equal "integers type" "integers" (cdr (assoc "type" s)))
    (test-equal "integers minimal: 1 field" 1 (length s)))

  (let ((s (integers #:min-value 10 #:max-value 20)))
    (test-equal "integers type with bounds" "integers" (cdr (assoc "type" s)))
    (test-equal "integers min_value" 10 (cdr (assoc "min_value" s)))
    (test-equal "integers max_value" 20 (cdr (assoc "max_value" s)))
    (test-equal "integers bounded: 3 fields" 3 (length s))))

(test-group "booleans schema"

  (let ((s (booleans)))
    (test-equal "booleans type" "booleans" (cdr (assoc "type" s)))
    (test-equal "booleans: 1 field" 1 (length s))))

(test-group "floats schema"

  (let ((s (floats)))
    (test-equal "floats type" "floats" (cdr (assoc "type" s))))

  (let ((s (floats #:allow-nan #f #:allow-infinity #f)))
    (test-equal "floats allow_nan" #f (cdr (assoc "allow_nan" s)))
    (test-equal "floats allow_infinity" #f (cdr (assoc "allow_infinity" s)))))

(test-group "text schema"

  (let ((s (text)))
    (test-equal "text type" "text" (cdr (assoc "type" s))))

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
    (test-equal "lists-of type" "lists" (cdr (assoc "type" s)))
    ;; elements should be the nested schema
    (let ((elts (cdr (assoc "elements" s))))
      (test-equal "lists-of elements type" "integers" (cdr (assoc "type" elts)))))

  (let ((s (lists-of (booleans) #:min-size 2 #:max-size 5)))
    (test-equal "lists-of with bounds: min_size" 2 (cdr (assoc "min_size" s)))
    (test-equal "lists-of with bounds: max_size" 5 (cdr (assoc "max_size" s)))))

(test-group "one-of schema"

  (let ((s (one-of (integers) (text) (booleans))))
    (test-equal "one_of type" "one_of" (cdr (assoc "type" s)))
    (let ((elts (cdr (assoc "elements" s))))
      (test-equal "one_of has 3 alternatives" 3 (length elts)))))

;;;; ── CBOR serialization of schemas ────────────────────────────────────────
;;
;; Schemas must survive CBOR round-trip since they're sent over the wire.

(test-group "schema CBOR round-trips"

  (for-each
    (lambda (pair)
      (let* ((label  (car pair))
             (schema (cdr pair))
             (decoded (cbor-decode (cbor-encode schema))))
        (test-equal (string-append label ": type survives CBOR")
          (cdr (assoc "type" schema))
          (cdr (assoc "type" decoded)))))
    (list
     (cons "integers" (integers #:min-value -100 #:max-value 100))
     (cons "booleans" (booleans))
     (cons "floats"   (floats #:min-value 0.0 #:max-value 1.0))
     (cons "text"     (text #:max-size 200))
     (cons "binary"   (binary))
     (cons "lists"    (lists-of (integers)))
     (cons "one_of"   (one-of (integers) (booleans))))))

;;;; ── Client-side combinators ──────────────────────────────────────────────
;;
;; gen-filter and gen-map use internal "_filter"/"_map" type markers.
;; These are NOT sent to the server — tc-draw handles them locally.

(test-group "gen-filter combinator"

  (let ((s (gen-filter (integers #:min-value 0 #:max-value 100)
                       even?)))
    (test-equal "gen-filter type marker" "_filter" (cdr (assoc "type" s)))
    (let ((inner (cdr (assoc "_schema" s))))
      (test-equal "gen-filter inner schema type" "integers"
        (cdr (assoc "type" inner))))
    (test-assert "gen-filter _pred is a procedure"
      (procedure? (cdr (assoc "_pred" s))))))

(test-group "gen-map combinator"

  (let ((s (gen-map (integers) (lambda (n) (* n 2)))))
    (test-equal "gen-map type marker" "_map" (cdr (assoc "type" s)))
    (let ((inner (cdr (assoc "_schema" s))))
      (test-equal "gen-map inner schema type" "integers"
        (cdr (assoc "type" inner))))
    (test-assert "gen-map _proc is a procedure"
      (procedure? (cdr (assoc "_proc" s))))))

(test-end "generators")
