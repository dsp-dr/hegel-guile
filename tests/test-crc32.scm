;;; tests/test-crc32.scm — CRC32 test vectors

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (hegel crc32)
             (rnrs bytevectors)
             (srfi srfi-64))

(test-begin "crc32")

;;; Standard test vector: "123456789" -> 0xCBF43926
(test-equal "standard-123456789"
  #xCBF43926
  (crc32 (string->utf8 "123456789")))

;;; Empty input -> 0x00000000
(test-equal "empty-input"
  #x00000000
  (crc32 (make-bytevector 0)))

;;; Single byte: "a" -> 0xE8B7BE43
(test-equal "single-byte-a"
  #xE8B7BE43
  (crc32 (string->utf8 "a")))

;;; Known value: "HEGL" (the magic bytes)
(test-equal "hegl-magic"
  #xC9E7349C
  (crc32 (string->utf8 "HEGL")))

;;; Incremental: update in two parts equals single computation
(let* ((part1 (string->utf8 "1234"))
       (part2 (string->utf8 "56789"))
       (full  (string->utf8 "123456789"))
       (crc-incremental
        (let* ((c1 (crc32-update #xFFFFFFFF part1))
               (c2 (crc32-update c1 part2)))
          (logand (logxor c2 #xFFFFFFFF) #xFFFFFFFF))))
  (test-equal "incremental-matches-full"
    (crc32 full)
    crc-incremental))

;;; All zeros
(test-equal "all-zeros-4"
  #x2144DF1C
  (crc32 (make-bytevector 4 0)))

;;; All ones (0xFF)
(test-equal "all-ones-4"
  #xFFFFFFFF
  (crc32 (make-bytevector 4 #xFF)))

(test-end "crc32")
