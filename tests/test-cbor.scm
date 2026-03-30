;;; tests/test-cbor.scm — CBOR codec round-trip tests

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel cbor)
             (srfi srfi-64)
             (rnrs bytevectors)
             (rnrs io ports))

(test-begin "cbor-codec")

;;; ── Unsigned integers ────────────────────────────────────────────────────────

(test-equal "encode/decode 0"   0   (cbor-decode (cbor-encode 0)))
(test-equal "encode/decode 23"  23  (cbor-decode (cbor-encode 23)))
(test-equal "encode/decode 24"  24  (cbor-decode (cbor-encode 24)))
(test-equal "encode/decode 255" 255 (cbor-decode (cbor-encode 255)))
(test-equal "encode/decode 256" 256 (cbor-decode (cbor-encode 256)))
(test-equal "encode/decode 65535" 65535 (cbor-decode (cbor-encode 65535)))
(test-equal "encode/decode large" 1000000 (cbor-decode (cbor-encode 1000000)))

;;; ── Negative integers ────────────────────────────────────────────────────────

(test-equal "encode/decode -1"   -1  (cbor-decode (cbor-encode -1)))
(test-equal "encode/decode -100" -100 (cbor-decode (cbor-encode -100)))

;;; ── Booleans ─────────────────────────────────────────────────────────────────

(test-equal "encode/decode #t" #t (cbor-decode (cbor-encode #t)))
(test-equal "encode/decode #f" #f (cbor-decode (cbor-encode #f)))

;;; ── Null ─────────────────────────────────────────────────────────────────────

(test-equal "encode/decode null" 'null (cbor-decode (cbor-encode 'null)))

;;; ── Strings ──────────────────────────────────────────────────────────────────

(test-equal "encode/decode empty string" "" (cbor-decode (cbor-encode "")))
(test-equal "encode/decode hello" "hello" (cbor-decode (cbor-encode "hello")))
(test-equal "encode/decode unicode" "こんにちは"
  (cbor-decode (cbor-encode "こんにちは")))

;;; ── Lists ────────────────────────────────────────────────────────────────────

(test-equal "encode/decode empty list" '() (cbor-decode (cbor-encode '())))
(test-equal "encode/decode list" '(1 2 3) (cbor-decode (cbor-encode '(1 2 3))))
(test-equal "encode/decode nested" '(1 (2 3) 4)
  (cbor-decode (cbor-encode '(1 (2 3) 4))))

;;; ── Maps (alists) ────────────────────────────────────────────────────────────

(define sample-msg
  (list (cons "type" "draw")
        (cons "schema"
              (list (cons "type" "integer")
                    (cons "min_value" 0)
                    (cons "max_value" 100)))))

(let ((decoded (cbor-decode (cbor-encode sample-msg))))
  (test-equal "map type field" "draw" (cdr (assoc "type" decoded)))
  (let ((schema (cdr (assoc "schema" decoded))))
    (test-equal "schema type" "integer" (cdr (assoc "type" schema)))
    (test-equal "schema min_value" 0 (cdr (assoc "min_value" schema)))
    (test-equal "schema max_value" 100 (cdr (assoc "max_value" schema)))))

;;; ── CBOR encode/decode round-trip via bytevector ────────────────────────────
;;; (Old framed port I/O removed: framing is now in packet.scm)

(let* ((val     (list (cons "type" "ok")))
       (encoded (cbor-encode val))
       (decoded (cbor-decode encoded)))
  (test-equal "bytevector round-trip" "ok" (cdr (assoc "type" decoded))))

;;; ── Regression: inexact integers encode as float, not integer ──────────────
;;; Fix from v0.7.1: (integer? 3.0) is #t in Guile, but 3.0 must encode as
;;; CBOR float64 (major type 7), not CBOR uint (major type 0).

(let* ((exact-bv   (cbor-encode 3))
       (inexact-bv (cbor-encode 3.0)))
  ;; Exact 3 → major type 0 (uint), single byte: 0x03
  (test-equal "exact 3 encodes as uint" #x03 (bytevector-u8-ref exact-bv 0))
  ;; Inexact 3.0 → major type 7 (float64), first byte: 0xfb
  (test-equal "inexact 3.0 encodes as float64" #xfb (bytevector-u8-ref inexact-bv 0))
  ;; They must NOT be the same encoding
  (test-assert "exact and inexact have different CBOR encodings"
    (not (equal? exact-bv inexact-bv)))
  ;; Round-trip: 3.0 must come back as inexact
  (let ((decoded (cbor-decode inexact-bv)))
    (test-assert "inexact 3.0 round-trips as inexact"
      (and (= decoded 3.0) (inexact? decoded)))))

(test-end "cbor-codec")
