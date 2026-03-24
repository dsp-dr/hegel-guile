;;; hegel/cbor.scm — Minimal CBOR codec for the Hegel protocol
;;; CBOR major types:
;;;   0=uint  1=negint  2=bytes  3=text  4=array  5=map  7=float/simple

(define-module (hegel cbor)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (ice-9 binary-ports)
  #:use-module (srfi srfi-1)
  #:export (cbor-encode
            cbor-decode
            cbor-encode-to-port
            cbor-decode-from-port
            open-hegel-output-port
            get-hegel-output-bytes))

;;;; ── Encoding ────────────────────────────────────────────────────────────────

(define (cbor-write-head! bv offset major-type additional)
  "Write one CBOR initial byte: major-type (0-7) and additional (0-23)."
  (bytevector-u8-set! bv offset (+ (* major-type 32) additional)))

(define (encode-uint-bytes mt n)
  "Encode major-type MT with unsigned value N into a bytevector."
  (cond
   ((< n 24)
    (let ((bv (make-bytevector 1)))
      (bytevector-u8-set! bv 0 (+ (* mt 32) n))
      bv))
   ((< n 256)
    (let ((bv (make-bytevector 2)))
      (bytevector-u8-set! bv 0 (+ (* mt 32) 24))
      (bytevector-u8-set! bv 1 n)
      bv))
   ((< n 65536)
    (let ((bv (make-bytevector 3)))
      (bytevector-u8-set! bv 0 (+ (* mt 32) 25))
      (bytevector-u16-set! bv 1 n (endianness big))
      bv))
   ((< n 4294967296)
    (let ((bv (make-bytevector 5)))
      (bytevector-u8-set! bv 0 (+ (* mt 32) 26))
      (bytevector-u32-set! bv 1 n (endianness big))
      bv))
   (else
    (let ((bv (make-bytevector 9)))
      (bytevector-u8-set! bv 0 (+ (* mt 32) 27))
      (bytevector-u64-set! bv 1 n (endianness big))
      bv))))

(define (bv-append . bvs)
  "Concatenate bytevectors."
  (let* ((total (apply + (map bytevector-length bvs)))
         (result (make-bytevector total 0)))
    (let loop ((bvs bvs) (offset 0))
      (if (null? bvs)
          result
          (let ((bv (car bvs)))
            (bytevector-copy! bv 0 result offset (bytevector-length bv))
            (loop (cdr bvs) (+ offset (bytevector-length bv))))))))

(define (cbor-encode val)
  "Encode VAL as a CBOR bytevector."
  (cond
   ;; Boolean: must come before integer check
   ((eq? val #t) (make-bytevector 1 #xf5))
   ((eq? val #f) (make-bytevector 1 #xf4))
   ;; Null / unspecified
   ((eq? val 'null) (make-bytevector 1 #xf6))
   ;; Unsigned integer
   ((and (integer? val) (>= val 0))
    (encode-uint-bytes 0 val))
   ;; Negative integer
   ((integer? val)
    (encode-uint-bytes 1 (- -1 val)))
   ;; Float (double)
   ((real? val)
    (let ((bv (make-bytevector 9)))
      (bytevector-u8-set! bv 0 #xfb)
      (bytevector-ieee-double-set! bv 1 (exact->inexact val) (endianness big))
      bv))
   ;; String
   ((string? val)
    (let* ((utf8 (string->utf8 val))
           (len  (bytevector-length utf8)))
      (bv-append (encode-uint-bytes 3 len) utf8)))
   ;; Bytevector
   ((bytevector? val)
    (let ((len (bytevector-length val)))
      (bv-append (encode-uint-bytes 2 len) val)))
   ;; List → CBOR array  (must NOT be an alist)
   ((and (list? val)
         (or (null? val)
             (not (pair? (car val)))
             (not (string? (caar val)))))
    (apply bv-append
           (encode-uint-bytes 4 (length val))
           (map cbor-encode val)))
   ;; Association list → CBOR map  (non-empty list of (string . any) pairs)
   ((and (list? val) (not (null? val)) (pair? (car val)))
    (apply bv-append
           (encode-uint-bytes 5 (length val))
           (append-map (lambda (pair)
                         (list (cbor-encode (car pair))
                               (cbor-encode (cdr pair))))
                       val)))
   (else
    (error "cbor-encode: unsupported type" val))))

(define (cbor-encode-to-port port val)
  "Write length-prefixed CBOR frame to PORT."
  (let* ((payload (cbor-encode val))
         (len     (bytevector-length payload))
         (header  (make-bytevector 4)))
    (bytevector-u32-set! header 0 len (endianness big))
    (put-bytevector port header)
    (put-bytevector port payload)
    (force-output port)))

;;;; ── Decoding ────────────────────────────────────────────────────────────────

(define (read-byte! port)
  (let ((b (get-u8 port)))
    (when (eof-object? b)
      (error "cbor-decode: unexpected end of input"))
    b))

(define (read-bytes! port n)
  (let ((bv (get-bytevector-n port n)))
    (when (or (eof-object? bv) (< (bytevector-length bv) n))
      (error "cbor-decode: short read" n))
    bv))

(define (decode-additional port additional)
  "Decode the additional-info field, reading extra bytes as needed."
  (cond
   ((< additional 24) additional)
   ((= additional 24) (read-byte! port))
   ((= additional 25)
    (bytevector-u16-ref (read-bytes! port 2) 0 (endianness big)))
   ((= additional 26)
    (bytevector-u32-ref (read-bytes! port 4) 0 (endianness big)))
   ((= additional 27)
    (bytevector-u64-ref (read-bytes! port 8) 0 (endianness big)))
   (else
    (error "cbor-decode: reserved additional info" additional))))

(define (cbor-decode-item port)
  "Decode one CBOR item from PORT."
  (let* ((initial    (read-byte! port))
         (major-type (ash initial -5))
         (additional (logand initial #x1f)))
    (case major-type
      ;; 0: unsigned integer
      ((0) (decode-additional port additional))
      ;; 1: negative integer
      ((1) (- -1 (decode-additional port additional)))
      ;; 2: byte string
      ((2)
       (let ((len (decode-additional port additional)))
         (read-bytes! port len)))
      ;; 3: text string
      ((3)
       (let* ((len  (decode-additional port additional))
              (raw  (read-bytes! port len)))
         (utf8->string raw)))
      ;; 4: array
      ((4)
       (let ((count (decode-additional port additional)))
         (let loop ((i 0) (acc '()))
           (if (= i count)
               (reverse acc)
               (loop (+ i 1) (cons (cbor-decode-item port) acc))))))
      ;; 5: map → alist
      ((5)
       (let ((count (decode-additional port additional)))
         (let loop ((i 0) (acc '()))
           (if (= i count)
               (reverse acc)
               (let* ((k (cbor-decode-item port))
                      (v (cbor-decode-item port)))
                 (loop (+ i 1) (cons (cons k v) acc)))))))
      ;; 7: float / simple
      ((7)
       (cond
        ((= additional 20) #f)          ; false
        ((= additional 21) #t)          ; true
        ((= additional 22) 'null)       ; null
        ((= additional 25)              ; float16 – approximate via double
         (let* ((bv (read-bytes! port 2))
                (bits (bytevector-u16-ref bv 0 (endianness big)))
                (exp  (logand (ash bits -10) #x1f))
                (mant (logand bits #x3ff))
                (sign (if (> (logand bits #x8000) 0) -1.0 1.0)))
           (* sign
              (if (= exp 0)
                  (* 5.96046e-8 mant)   ; subnormal
                  (* (expt 2.0 (- exp 15))
                     (+ 1.0 (/ mant 1024.0)))))))
        ((= additional 26)              ; float32
         (bytevector-ieee-single-ref (read-bytes! port 4) 0 (endianness big)))
        ((= additional 27)              ; float64
         (bytevector-ieee-double-ref (read-bytes! port 8) 0 (endianness big)))
        (else (error "cbor-decode: unsupported simple value" additional))))
      (else
       (error "cbor-decode: unsupported major type" major-type)))))

(define (cbor-decode bv)
  "Decode CBOR from a complete bytevector BV."
  (let ((port (open-bytevector-input-port bv)))
    (cbor-decode-item port)))

(define (cbor-decode-from-port port)
  "Read one length-prefixed CBOR frame from binary PORT."
  (let* ((header  (read-bytes! port 4))
         (len     (bytevector-u32-ref header 0 (endianness big)))
         (payload (read-bytes! port len)))
    (cbor-decode payload)))
