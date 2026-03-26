;;; hegel/crc32.scm — CRC32 checksum for HEGL packet integrity
;;;
;;; Pure Scheme implementation using the standard polynomial 0xEDB88320
;;; (reflected form of 0x04C11DB7). Used by the HEGL packet framing to
;;; verify header + payload integrity.

(define-module (hegel crc32)
  #:use-module (rnrs bytevectors)
  #:export (crc32
            crc32-update))

;;;; ── Lookup table ─────────────────────────────────────────────────────────────

(define %crc32-table
  (let ((table (make-vector 256 0)))
    (let loop-i ((i 0))
      (when (< i 256)
        (let loop-j ((j 0) (crc i))
          (if (= j 8)
              (begin
                (vector-set! table i crc)
                (loop-i (+ i 1)))
              (if (odd? crc)
                  (loop-j (+ j 1)
                          (logxor (ash crc -1) #xEDB88320))
                  (loop-j (+ j 1)
                          (ash crc -1)))))))
    table))

;;;; ── Core ─────────────────────────────────────────────────────────────────────

(define (crc32-update crc bv)
  "Update CRC with bytes from bytevector BV. CRC should be the
running CRC value (initial: #xFFFFFFFF). Returns updated CRC (not finalized)."
  (let ((len (bytevector-length bv)))
    (let loop ((i 0) (c crc))
      (if (= i len)
          c
          (let* ((byte (bytevector-u8-ref bv i))
                 (index (logand (logxor c byte) #xFF)))
            (loop (+ i 1)
                  (logxor (ash c -8)
                          (vector-ref %crc32-table index))))))))

(define (crc32 bv)
  "Compute CRC32 checksum of bytevector BV. Returns an exact uint32."
  (logand (logxor (crc32-update #xFFFFFFFF bv) #xFFFFFFFF)
          #xFFFFFFFF))
