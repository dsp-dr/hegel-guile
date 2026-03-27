;;; hegel.scm — Top-level module: re-exports the public API

(define-module (hegel)
  #:use-module (hegel generators)
  #:use-module (hegel test)
  #:export (%hegel-guile-version)
  #:re-export (;; Generators
               integers booleans floats text binary
               null-values sampled-from const-value
               lists-of one-of gen-filter gen-map
               define-composite
               ;; Test API
               define-hegel-test hegel-test run-hegel-tests!
               ;; TestCase API (re-exported via hegel test)
               tc-draw tc-assume))

;;; Version tracks Hegel protocol version: 0.7.x for protocol 0.7
;;; Patch bumps (0.7.1 -> 0.7.2) for hegel-guile fixes.
;;; Minor bump (0.7 -> 0.8) only when hegel-core bumps protocol version.
(define %hegel-guile-version "0.7.1")
