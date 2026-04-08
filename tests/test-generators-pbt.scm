;;; tests/test-generators-pbt.scm — PBT-style property tests for generator schemas
;;; Bead: hegel-guile-x99 (self-host PBT)
;;;
;;; Tests algebraic properties of schema combinators: composition,
;;; CBOR serializability, structural invariants, and idempotence.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel generators)
             (hegel cbor)
             (srfi srfi-1)
             (srfi srfi-64))

(test-begin "generators-pbt")

;;;; ── Helpers ─────────────────────────────────────────────────────────────────

(define (schema-type schema)
  "Extract the type field from a schema alist, or #f if absent."
  (let ((pair (assoc "type" schema)))
    (and pair (cdr pair))))

(define (schema-has-key? schema key)
  "Return #t if SCHEMA alist has KEY."
  (and (assoc key schema) #t))

(define (cbor-round-trip-schema schema)
  "CBOR encode/decode a schema, stripping any procedure-valued keys
   (which can't be serialized)."
  (let ((serializable
         (filter (lambda (pair) (not (procedure? (cdr pair)))) schema)))
    (cbor-decode (cbor-encode serializable))))

;;;; ── Property: all type-based schemas have exactly one type field ────────────

(test-group "property: type-based schemas have type field"
  (let ((schemas
         (list (cons "integers"    (integers))
               (cons "integers/b"  (integers #:min-value -10 #:max-value 10))
               (cons "booleans"    (booleans))
               (cons "booleans/p"  (booleans #:p 0.5))
               (cons "floats"      (floats))
               (cons "floats/b"    (floats #:min-value 0.0 #:max-value 1.0))
               (cons "text"        (text))
               (cons "text/b"      (text #:min-size 1 #:max-size 50))
               (cons "binary"      (binary))
               (cons "binary/b"    (binary #:min-size 0 #:max-size 100))
               (cons "lists-of"    (lists-of (integers)))
               (cons "null-values" (null-values)))))
    (for-each
      (lambda (pair)
        (let ((label (car pair))
              (schema (cdr pair)))
          (test-assert (format #f "~a has type field" label)
            (schema-has-key? schema "type"))
          ;; Exactly one "type" key
          (test-equal (format #f "~a has exactly one type key" label)
            1 (count (lambda (p) (equal? (car p) "type")) schema))))
      schemas)))

;;;; ── Property: top-level-key schemas have NO type field ─────────────────────

(test-group "property: top-level-key schemas lack type field"
  (let ((schemas
         (list (cons "one-of"       (one-of (integers) (text)))
               (cons "sampled-from" (sampled-from '("a" "b")))
               (cons "const-value"  (const-value 42)))))
    (for-each
      (lambda (pair)
        (let ((label (car pair))
              (schema (cdr pair)))
          (test-assert (format #f "~a has no type field" label)
            (not (schema-has-key? schema "type")))))
      schemas)))

;;;; ── Property: optional params only appear when specified ───────────────────

(test-group "property: optional params absent by default"
  ;; integers without opts has only type
  (test-equal "integers default: 1 field"
    1 (length (integers)))
  (test-assert "integers default: no min_value"
    (not (schema-has-key? (integers) "min_value")))
  (test-assert "integers default: no max_value"
    (not (schema-has-key? (integers) "max_value")))

  ;; booleans without opts has only type
  (test-equal "booleans default: 1 field"
    1 (length (booleans)))
  (test-assert "booleans default: no p"
    (not (schema-has-key? (booleans) "p")))

  ;; floats without opts has only type
  (test-equal "floats default: 1 field"
    1 (length (floats)))

  ;; text without opts has only type
  (test-equal "text default: 1 field"
    1 (length (text)))

  ;; binary without opts has only type
  (test-equal "binary default: 1 field"
    1 (length (binary)))

  ;; lists-of without opts has type + elements
  (test-equal "lists-of default: 2 fields"
    2 (length (lists-of (integers)))))

;;;; ── Property: specifying all params includes them all ──────────────────────

(test-group "property: all params present when specified"
  (let ((s (integers #:min-value -100 #:max-value 100)))
    (test-equal "integers all: 3 fields" 3 (length s))
    (test-equal "integers min_value" -100 (cdr (assoc "min_value" s)))
    (test-equal "integers max_value" 100 (cdr (assoc "max_value" s))))

  (let ((s (floats #:min-value -1.0 #:max-value 1.0
                   #:allow-nan #f #:allow-infinity #f
                   #:width 32 #:exclude-min #t #:exclude-max #t)))
    (test-equal "floats all params: 8 fields" 8 (length s))
    (test-equal "floats width" 32 (cdr (assoc "width" s)))
    (test-equal "floats allow_nan" #f (cdr (assoc "allow_nan" s)))
    (test-equal "floats exclude_min" #t (cdr (assoc "exclude_min" s)))
    (test-equal "floats exclude_max" #t (cdr (assoc "exclude_max" s))))

  (let ((s (lists-of (text) #:min-size 5 #:max-size 50 #:unique #t)))
    (test-equal "lists-of all params: 5 fields" 5 (length s))
    (test-equal "lists-of unique" #t (cdr (assoc "unique" s)))))

;;;; ── Property: schemas survive CBOR round-trip ──────────────────────────────

(test-group "property: schema CBOR round-trip"
  (let ((type-schemas
         (list (integers)
               (integers #:min-value -50 #:max-value 50)
               (booleans)
               (booleans #:p 0.3)
               (floats)
               (floats #:min-value 0.0 #:max-value 100.0)
               (text)
               (text #:min-size 1 #:max-size 200)
               (binary)
               (binary #:min-size 0 #:max-size 512)
               (lists-of (integers))
               (lists-of (text) #:min-size 2 #:max-size 10)
               (null-values))))
    (for-each
      (lambda (schema)
        (let ((decoded (cbor-round-trip-schema schema)))
          ;; Type field must survive
          (test-equal (format #f "type=~a survives CBOR" (schema-type schema))
            (schema-type schema) (schema-type decoded))
          ;; Field count must match
          (test-equal (format #f "type=~a: field count survives CBOR"
                        (schema-type schema))
            (length schema) (length decoded))))
      type-schemas))

  ;; Top-level key schemas
  (let* ((schema (one-of (integers) (booleans) (text)))
         (decoded (cbor-round-trip-schema schema)))
    (test-assert "one_of survives CBOR"
      (schema-has-key? decoded "one_of"))
    (test-equal "one_of: 3 alternatives after CBOR"
      3 (length (cdr (assoc "one_of" decoded)))))

  (let* ((schema (sampled-from '(1 2 3 4 5)))
         (decoded (cbor-round-trip-schema schema)))
    (test-assert "sampled_from survives CBOR"
      (schema-has-key? decoded "sampled_from"))
    (test-equal "sampled_from values after CBOR"
      '(1 2 3 4 5) (cdr (assoc "sampled_from" decoded))))

  (let* ((schema (const-value "fixed"))
         (decoded (cbor-round-trip-schema schema)))
    (test-equal "const value after CBOR"
      "fixed" (cdr (assoc "const" decoded)))))

;;;; ── Property: nested schemas preserve structure through CBOR ────────────────

(test-group "property: nested schema CBOR round-trip"
  ;; lists-of with nested integer schema
  (let* ((schema (lists-of (integers #:min-value 0 #:max-value 255)))
         (decoded (cbor-round-trip-schema schema)))
    (let ((elements (cdr (assoc "elements" decoded))))
      (test-equal "nested: elements type is integer"
        "integer" (cdr (assoc "type" elements)))
      (test-equal "nested: elements min_value"
        0 (cdr (assoc "min_value" elements)))
      (test-equal "nested: elements max_value"
        255 (cdr (assoc "max_value" elements)))))

  ;; one-of with mixed nested schemas
  (let* ((schema (one-of (integers #:min-value 0)
                         (text #:max-size 10)
                         (booleans)))
         (decoded (cbor-round-trip-schema schema))
         (alts (cdr (assoc "one_of" decoded))))
    (test-equal "nested one_of: 3 alternatives" 3 (length alts))
    (test-equal "nested one_of[0] type" "integer"
      (cdr (assoc "type" (list-ref alts 0))))
    (test-equal "nested one_of[0] min_value" 0
      (cdr (assoc "min_value" (list-ref alts 0))))
    (test-equal "nested one_of[1] type" "string"
      (cdr (assoc "type" (list-ref alts 1))))
    (test-equal "nested one_of[1] max_size" 10
      (cdr (assoc "max_size" (list-ref alts 1))))
    (test-equal "nested one_of[2] type" "boolean"
      (cdr (assoc "type" (list-ref alts 2))))))

;;;; ── Property: gen-filter wraps inner schema correctly ──────────────────────

(test-group "property: gen-filter structure"
  (let ((inner-schemas
         (list (integers)
               (integers #:min-value 0 #:max-value 100)
               (text)
               (floats #:min-value 0.0))))
    (for-each
      (lambda (inner)
        (let ((filtered (gen-filter inner even?)))
          (test-equal "gen-filter type is _filter"
            "_filter" (schema-type filtered))
          (test-assert "gen-filter has _schema"
            (schema-has-key? filtered "_schema"))
          (test-assert "gen-filter has _pred"
            (schema-has-key? filtered "_pred"))
          (test-assert "gen-filter _pred is procedure"
            (procedure? (cdr (assoc "_pred" filtered))))
          ;; Inner schema is preserved
          (test-equal "gen-filter inner type preserved"
            (schema-type inner)
            (schema-type (cdr (assoc "_schema" filtered))))))
      inner-schemas)))

;;;; ── Property: gen-map wraps inner schema correctly ─────────────────────────

(test-group "property: gen-map structure"
  (let ((inner-schemas
         (list (integers)
               (text #:min-size 1)
               (booleans))))
    (for-each
      (lambda (inner)
        (let ((mapped (gen-map inner identity)))
          (test-equal "gen-map type is _map"
            "_map" (schema-type mapped))
          (test-assert "gen-map has _schema"
            (schema-has-key? mapped "_schema"))
          (test-assert "gen-map has _proc"
            (schema-has-key? mapped "_proc"))
          (test-assert "gen-map _proc is procedure"
            (procedure? (cdr (assoc "_proc" mapped))))
          ;; Inner schema is preserved
          (test-equal "gen-map inner type preserved"
            (schema-type inner)
            (schema-type (cdr (assoc "_schema" mapped))))))
      inner-schemas)))

;;;; ── Property: gen-filter and gen-map compose ───────────────────────────────

(test-group "property: combinator composition"
  ;; filter(map(integers, double), even?)
  (let* ((doubled (gen-map (integers #:min-value 0 #:max-value 50)
                           (lambda (n) (* n 2))))
         (even-doubled (gen-filter doubled even?)))
    (test-equal "composed: outer type is _filter"
      "_filter" (schema-type even-doubled))
    (let ((inner (cdr (assoc "_schema" even-doubled))))
      (test-equal "composed: middle type is _map"
        "_map" (schema-type inner))
      (let ((innermost (cdr (assoc "_schema" inner))))
        (test-equal "composed: innermost type is integer"
          "integer" (schema-type innermost)))))

  ;; map(filter(integers, even?), negate)
  (let* ((evens (gen-filter (integers) even?))
         (neg-evens (gen-map evens (lambda (n) (- n)))))
    (test-equal "composed: outer type is _map"
      "_map" (schema-type neg-evens))
    (let ((inner (cdr (assoc "_schema" neg-evens))))
      (test-equal "composed: inner type is _filter"
        "_filter" (schema-type inner)))))

;;;; ── Property: schema keys are always strings ───────────────────────────────

(test-group "property: all schema keys are strings"
  (let ((all-schemas
         (list (integers)
               (integers #:min-value -10 #:max-value 10)
               (booleans)
               (booleans #:p 0.9)
               (floats)
               (floats #:width 32 #:allow-nan #f)
               (text)
               (text #:min-size 1 #:max-size 50)
               (binary)
               (binary #:min-size 0 #:max-size 256)
               (lists-of (integers))
               (lists-of (text) #:min-size 1 #:max-size 10 #:unique #t)
               (one-of (integers) (text))
               (null-values)
               (sampled-from '("a" "b"))
               (const-value 42)
               (gen-filter (integers) even?)
               (gen-map (integers) identity))))
    (for-each
      (lambda (schema)
        (test-assert (format #f "all keys are strings in ~a"
                       (or (schema-type schema) "top-level"))
          (every (lambda (pair) (string? (car pair))) schema)))
      all-schemas)))

(test-end "generators-pbt")
