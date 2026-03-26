;;; hegel.scm — Top-level module: re-exports the public API

(define-module (hegel)
  #:use-module (hegel generators)
  #:use-module (hegel test)
  #:re-export (;; Generators
               integers booleans floats text binary
               lists-of one-of gen-filter gen-map
               define-composite
               ;; Test API
               define-hegel-test hegel-test run-hegel-tests!
               ;; TestCase API (re-exported via hegel test)
               tc-draw tc-assume))
