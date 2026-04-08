;;; tests/test-cbor-pbt.scm — PBT-style round-trip property tests for CBOR codec
;;; Bead: hegel-guile-x99 (self-host PBT)
;;;
;;; These tests exercise CBOR encode/decode invariants over ranges of inputs,
;;; simulating property-based testing without a live hegel-core server.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel cbor)
             (srfi srfi-1)
             (srfi srfi-64)
             (rnrs bytevectors))

(test-begin "cbor-pbt")

;;;; ── Helpers ─────────────────────────────────────────────────────────────────

(define (cbor-round-trip val)
  "Encode VAL to CBOR, decode it back."
  (cbor-decode (cbor-encode val)))

;;;; ── Property: integer round-trip across boundary values ─────────────────────
;;
;; For all exact integers in key ranges (around CBOR encoding thresholds),
;; encode then decode must yield the original value.

(test-group "property: uint boundary round-trip"
  ;; CBOR uint encoding thresholds: 0-23 (inline), 24-255 (1-byte),
  ;; 256-65535 (2-byte), 65536-4294967295 (4-byte)
  (let ((boundary-values
         '(0 1 22 23 24 25 127 128 255 256 257
           65534 65535 65536 65537
           16777215 16777216
           4294967295 4294967296)))
    (for-each
      (lambda (n)
        (test-equal (format #f "uint ~a round-trips" n)
          n (cbor-round-trip n)))
      boundary-values)))

(test-group "property: negint boundary round-trip"
  (let ((boundary-values
         '(-1 -2 -23 -24 -25 -128 -129 -255 -256 -257
           -65535 -65536 -65537
           -4294967296 -4294967297)))
    (for-each
      (lambda (n)
        (test-equal (format #f "negint ~a round-trips" n)
          n (cbor-round-trip n)))
      boundary-values)))

;;;; ── Property: string round-trip preserves length and content ────────────────

(test-group "property: string round-trip"
  (let ((test-strings
         (list ""
               "a"
               (make-string 23 #\x)     ; inline length
               (make-string 24 #\y)     ; 1-byte length
               (make-string 255 #\z)    ; max 1-byte
               (make-string 256 #\w)    ; 2-byte length
               "hello world"
               "line1\nline2\ttab"
               "\""                      ; quote character
               "\x00;"                   ; null byte in string
               )))
    (for-each
      (lambda (s)
        (let ((decoded (cbor-round-trip s)))
          (test-equal (format #f "string len=~a content preserved" (string-length s))
            s decoded)
          (test-equal (format #f "string len=~a length preserved" (string-length s))
            (string-length s) (string-length decoded))))
      test-strings)))

;;;; ── Property: boolean identity ──────────────────────────────────────────────

(test-group "property: boolean identity"
  (test-assert "true round-trips to exact #t"
    (eq? #t (cbor-round-trip #t)))
  (test-assert "false round-trips to exact #f"
    (eq? #f (cbor-round-trip #f)))
  ;; CBOR booleans must not be confused with integers
  (test-assert "#t is not 1 after round-trip"
    (not (equal? 1 (cbor-round-trip #t))))
  (test-assert "#f is not 0 after round-trip"
    (not (equal? 0 (cbor-round-trip #f)))))

;;;; ── Property: null identity ─────────────────────────────────────────────────

(test-group "property: null identity"
  (test-assert "null round-trips to symbol null"
    (eq? 'null (cbor-round-trip 'null)))
  (test-assert "null is not #f"
    (not (eq? #f (cbor-round-trip 'null)))))

;;;; ── Property: float round-trip preserves exactness ──────────────────────────

(test-group "property: float round-trip"
  (let ((test-floats
         (list 0.0 -0.0 1.0 -1.0
               0.5 -0.5
               1.0e10 -1.0e10
               1.0e-10 -1.0e-10
               3.14159265358979
               1.7976931348623157e+308   ; near max double
               2.2250738585072014e-308   ; near min normal double
               )))
    (for-each
      (lambda (f)
        (let ((decoded (cbor-round-trip f)))
          (test-assert (format #f "float ~a round-trips as inexact" f)
            (inexact? decoded))
          (test-equal (format #f "float ~a value preserved" f)
            f decoded)))
      test-floats))
  ;; Special: NaN round-trips as NaN
  (let ((decoded (cbor-round-trip +nan.0)))
    (test-assert "NaN round-trips as NaN"
      (nan? decoded)))
  ;; Special: infinities
  (test-equal "+inf round-trips" +inf.0 (cbor-round-trip +inf.0))
  (test-equal "-inf round-trips" -inf.0 (cbor-round-trip -inf.0)))

;;;; ── Property: exact vs inexact integers have different encodings ────────────

(test-group "property: exact/inexact integer distinction"
  (for-each
    (lambda (n)
      (let* ((exact-enc   (cbor-encode n))
             (inexact-enc (cbor-encode (exact->inexact n))))
        (test-assert (format #f "~a: exact and inexact encode differently" n)
          (not (equal? exact-enc inexact-enc)))
        ;; Exact integer decodes as exact
        (test-assert (format #f "~a: exact decodes as exact" n)
          (exact? (cbor-decode exact-enc)))
        ;; Inexact decodes as inexact
        (test-assert (format #f "~a: inexact decodes as inexact" n)
          (inexact? (cbor-decode inexact-enc)))))
    '(0 1 42 255 1000)))

;;;; ── Property: list round-trip preserves structure ───────────────────────────

(test-group "property: list round-trip"
  (let ((test-lists
         (list '()
               '(1)
               '(1 2 3 4 5)
               '("a" "b" "c")
               '(#t #f #t)
               (list 'null 'null)
               '(1 "two" #t)            ; heterogeneous
               (list (list 1 2) (list 3 4))  ; nested
               (make-list 50 0)          ; longer list
               )))
    (for-each
      (lambda (lst)
        (test-equal (format #f "list len=~a round-trips" (length lst))
          lst (cbor-round-trip lst)))
      test-lists)))

;;;; ── Property: alist (map) round-trip preserves key-value pairs ─────────────

(test-group "property: alist round-trip"
  (let ((test-maps
         (list
          ;; Single key
          (list (cons "key" "value"))
          ;; Multiple keys
          (list (cons "a" 1) (cons "b" 2) (cons "c" 3))
          ;; Nested map
          (list (cons "outer"
                      (list (cons "inner" "deep"))))
          ;; Mixed value types
          (list (cons "int" 42)
                (cons "str" "hello")
                (cons "bool" #t)
                (cons "nil" 'null)
                (cons "list" '(1 2 3)))
          ;; Protocol-like message
          (list (cons "type" "draw")
                (cons "schema"
                      (list (cons "type" "integer")
                            (cons "min_value" 0)
                            (cons "max_value" 100))))
          ;; Empty-valued keys
          (list (cons "empty_string" "")
                (cons "zero" 0)
                (cons "false" #f)))))
    (for-each
      (lambda (alist)
        (let ((decoded (cbor-round-trip alist)))
          ;; All keys survive
          (test-equal (format #f "alist ~a keys: count preserved"
                        (length alist))
            (length alist) (length decoded))
          ;; Each key-value pair is preserved
          (for-each
            (lambda (pair)
              (test-equal (format #f "alist key ~a preserved" (car pair))
                (cdr pair) (cdr (assoc (car pair) decoded))))
            alist)))
      test-maps)))

;;;; ── Property: bytevector round-trip ─────────────────────────────────────────

(test-group "property: bytevector round-trip"
  (let ((test-bvs
         (list (make-bytevector 0)
               (make-bytevector 1 #xFF)
               (make-bytevector 23 #xAB)   ; inline length
               (make-bytevector 24 #xCD)   ; 1-byte length
               (make-bytevector 256 #x42)  ; 2-byte length
               (u8-list->bytevector '(0 1 2 3 4 5 6 7)))))
    (for-each
      (lambda (bv)
        (test-equal (format #f "bytevector len=~a round-trips"
                      (bytevector-length bv))
          bv (cbor-round-trip bv)))
      test-bvs)))

;;;; ── Property: encoding is deterministic ─────────────────────────────────────

(test-group "property: encoding determinism"
  (let ((values (list 0 -1 42 "hello" #t #f 'null '(1 2 3)
                      (list (cons "k" "v"))
                      3.14)))
    (for-each
      (lambda (val)
        (test-equal (format #f "~a encodes identically twice" val)
          (cbor-encode val) (cbor-encode val)))
      values)))

(test-end "cbor-pbt")
