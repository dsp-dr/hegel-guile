;;; tests/test-crc32-pbt.scm — PBT-style property tests for CRC32
;;; Bead: hegel-guile-x99 (self-host PBT)
;;;
;;; Tests CRC32 properties: known vectors, incremental consistency,
;;; and algebraic invariants over varied inputs.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel crc32)
             (rnrs bytevectors)
             (srfi srfi-64))

(test-begin "crc32-pbt")

;;;; ── Helpers ─────────────────────────────────────────────────────────────────

(define (bv-concat bv1 bv2)
  "Concatenate two bytevectors."
  (let* ((len1 (bytevector-length bv1))
         (len2 (bytevector-length bv2))
         (result (make-bytevector (+ len1 len2))))
    (bytevector-copy! bv1 0 result 0 len1)
    (bytevector-copy! bv2 0 result len1 len2)
    result))

;;;; ── Property: known test vectors from RFC 3720 / ITU-T V.42 ────────────────

(test-group "property: known test vectors"
  ;; Standard CRC32 test vectors
  (let ((vectors
         (list
          (cons (string->utf8 "123456789") #xCBF43926)
          (cons (string->utf8 "")          #x00000000)
          (cons (string->utf8 "a")         #xE8B7BE43)
          (cons (string->utf8 "abc")       #x352441C2)
          (cons (string->utf8 "message digest") #x20159D7F)
          (cons (string->utf8 "abcdefghijklmnopqrstuvwxyz") #x4C2750BD)
          (cons (string->utf8 "HEGL")      #xC9E7349C))))
    (for-each
      (lambda (pair)
        (test-equal (format #f "crc32(~a) matches known value"
                      (utf8->string (car pair)))
          (cdr pair) (crc32 (car pair))))
      vectors)))

;;;; ── Property: incremental == single-pass ───────────────────────────────────
;;
;; For any partition of a bytevector into two parts,
;; crc32-update applied sequentially must equal crc32 on the whole.

(test-group "property: incremental equals single-pass"
  (let ((test-strings
         (list "123456789" "hello world" "HEGL" "abcdef" ""
               "a" "ab" "abc" "abcd")))
    (for-each
      (lambda (s)
        (let ((full-bv (string->utf8 s))
              (full-crc (crc32 (string->utf8 s))))
          ;; Try every possible split point
          (let ((len (bytevector-length full-bv)))
            (let loop ((split 0))
              (when (<= split len)
                (let* ((part1 (let ((bv (make-bytevector split)))
                                (bytevector-copy! full-bv 0 bv 0 split)
                                bv))
                       (part2 (let ((bv (make-bytevector (- len split))))
                                (bytevector-copy! full-bv split bv 0 (- len split))
                                bv))
                       (crc-inc
                        (let* ((c1 (crc32-update #xFFFFFFFF part1))
                               (c2 (crc32-update c1 part2)))
                          (logand (logxor c2 #xFFFFFFFF) #xFFFFFFFF))))
                  (test-equal (format #f "~a split@~a: incremental=full" s split)
                    full-crc crc-inc))
                (loop (+ split 1)))))))
      test-strings)))

;;;; ── Property: single-byte inputs cover full byte range ─────────────────────
;;
;; CRC32 of each single byte should be unique (collision-free for 1-byte inputs).

(test-group "property: single-byte uniqueness"
  (let ((crcs (let loop ((i 0) (acc '()))
                (if (= i 256)
                    acc
                    (loop (+ i 1)
                          (cons (crc32 (make-bytevector 1 i)) acc))))))
    ;; All 256 single-byte CRCs should be distinct
    (let ((unique-count
           (let loop ((remaining crcs) (seen '()) (count 0))
             (if (null? remaining)
                 count
                 (if (member (car remaining) seen)
                     (loop (cdr remaining) seen count)
                     (loop (cdr remaining)
                           (cons (car remaining) seen)
                           (+ count 1)))))))
      (test-equal "256 single-byte inputs produce 256 distinct CRCs"
        256 unique-count))))

;;;; ── Property: all-zeros and all-ones are distinct ──────────────────────────

(test-group "property: trivial inputs differ"
  (let loop ((len 1))
    (when (<= len 8)
      (let ((crc-zeros (crc32 (make-bytevector len 0)))
            (crc-ones  (crc32 (make-bytevector len #xFF))))
        (test-assert (format #f "zeros(~a) != ones(~a)" len len)
          (not (= crc-zeros crc-ones))))
      (loop (+ len 1)))))

;;;; ── Property: prepending a byte changes the CRC ───────────────────────────

(test-group "property: prepending changes CRC"
  (let ((base-bv (string->utf8 "test")))
    (let loop ((b 0))
      (when (< b 256)
        (let* ((prefix (make-bytevector 1 b))
               (extended (bv-concat prefix base-bv)))
          (test-assert (format #f "prepend byte ~a changes CRC" b)
            (not (= (crc32 base-bv) (crc32 extended)))))
        ;; Sample every 51st byte to keep test count reasonable
        (loop (+ b 51))))))

;;;; ── Property: CRC32 output is always 32-bit ───────────────────────────────

(test-group "property: output is 32-bit"
  (let ((inputs
         (list (make-bytevector 0)
               (make-bytevector 1 0)
               (make-bytevector 1 #xFF)
               (string->utf8 "hello")
               (make-bytevector 1000 #x42))))
    (for-each
      (lambda (bv)
        (let ((c (crc32 bv)))
          (test-assert (format #f "crc32 of ~a bytes is non-negative"
                         (bytevector-length bv))
            (>= c 0))
          (test-assert (format #f "crc32 of ~a bytes fits in 32 bits"
                         (bytevector-length bv))
            (<= c #xFFFFFFFF))))
      inputs)))

(test-end "crc32-pbt")
