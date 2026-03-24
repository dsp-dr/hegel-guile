;;; examples/ledger.scm — Double-entry bookkeeping property tests
;;;
;;; A minimal double-entry ledger. The fundamental invariant:
;;; the sum of all debits equals the sum of all credits (the books balance).

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel)
             (srfi srfi-1))

;;;; ── Ledger Data Model ────────────────────────────────────────────────────

;; An entry is (account amount side) where side is 'debit or 'credit.
;; A transaction is a list of entries that must balance.

(define (make-entry account amount side)
  (list account amount side))

(define (entry-account e) (list-ref e 0))
(define (entry-amount e)  (list-ref e 1))
(define (entry-side e)    (list-ref e 2))

(define (make-transaction . entries) entries)

(define (transaction-balanced? txn)
  "Sum of debits = sum of credits."
  (let ((debits  (fold + 0 (map entry-amount
                                (filter (lambda (e) (eq? (entry-side e) 'debit)) txn))))
        (credits (fold + 0 (map entry-amount
                                (filter (lambda (e) (eq? (entry-side e) 'credit)) txn)))))
    (= debits credits)))

(define (ledger-balanced? ledger)
  "All transactions in LEDGER are balanced."
  (every transaction-balanced? ledger))

(define (account-balance ledger account)
  "Net balance for ACCOUNT across all transactions. Debits positive, credits negative."
  (fold + 0
        (map (lambda (entry)
               (if (eq? (entry-side entry) 'debit)
                   (entry-amount entry)
                   (- (entry-amount entry))))
             (filter (lambda (entry)
                       (= (entry-account entry) account))
                     (apply append ledger)))))

;;;; ── Property Tests ───────────────────────────────────────────────────────

(define-hegel-test (test-single-transaction-balances tc #:test-cases 300)
  "A transaction with one debit and one credit of the same amount balances."
  (let* ((amount  (tc-draw tc (integers #:min-value 1 #:max-value 1000000)))
         (acct-a  (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (acct-b  (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (txn (make-transaction
               (make-entry acct-a amount 'debit)
               (make-entry acct-b amount 'credit))))
    (unless (transaction-balanced? txn)
      (error "single transaction not balanced" txn))))

(define-hegel-test (test-multi-entry-transaction-balances tc #:test-cases 200)
  "A transaction splitting one debit into two credits balances."
  (let* ((total   (tc-draw tc (integers #:min-value 2 #:max-value 1000000)))
         (split   (tc-draw tc (integers #:min-value 1 #:max-value (- total 1))))
         (acct-a  (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (acct-b  (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (acct-c  (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         (txn (make-transaction
               (make-entry acct-a total 'debit)
               (make-entry acct-b split 'credit)
               (make-entry acct-c (- total split) 'credit))))
    (unless (transaction-balanced? txn)
      (error "multi-entry transaction not balanced" txn))))

(define-hegel-test (test-ledger-total-balance-zero tc #:test-cases 200)
  "Total across all accounts in a balanced ledger is zero."
  (let* ((n-txns (tc-draw tc (integers #:min-value 1 #:max-value 10)))
         (ledger
          (let loop ((i 0) (txns '()))
            (if (= i n-txns)
                txns
                (let* ((amount (tc-draw tc (integers #:min-value 1 #:max-value 10000)))
                       (acct-a (tc-draw tc (integers #:min-value 1 #:max-value 20)))
                       (acct-b (tc-draw tc (integers #:min-value 1 #:max-value 20)))
                       (txn (make-transaction
                             (make-entry acct-a amount 'debit)
                             (make-entry acct-b amount 'credit))))
                  (loop (+ i 1) (cons txn txns)))))))
    (unless (ledger-balanced? ledger)
      (error "ledger not balanced" ledger))
    ;; Sum of all account balances must be zero
    (let* ((all-accounts (delete-duplicates
                          (map entry-account (apply append ledger))))
           (total (fold + 0 (map (lambda (a) (account-balance ledger a))
                                 all-accounts))))
      (unless (= total 0)
        (error "total balance not zero" total all-accounts)))))

(define-hegel-test (test-transfer-preserves-total tc #:test-cases 300)
  "Transferring between accounts doesn't change total assets."
  (let* ((initial-a (tc-draw tc (integers #:min-value 100 #:max-value 10000)))
         (initial-b (tc-draw tc (integers #:min-value 100 #:max-value 10000)))
         (transfer  (tc-draw tc (integers #:min-value 1 #:max-value 100)))
         ;; Initial deposits
         (txn1 (make-transaction
                (make-entry 1 initial-a 'debit)
                (make-entry 0 initial-a 'credit)))
         (txn2 (make-transaction
                (make-entry 2 initial-b 'debit)
                (make-entry 0 initial-b 'credit)))
         ;; Transfer from account 1 to account 2
         (txn3 (make-transaction
                (make-entry 2 transfer 'debit)
                (make-entry 1 transfer 'credit)))
         (ledger (list txn1 txn2 txn3))
         (bal-1 (account-balance ledger 1))
         (bal-2 (account-balance ledger 2)))
    (unless (= (+ bal-1 bal-2) (+ initial-a initial-b))
      (error "transfer changed total" initial-a initial-b transfer bal-1 bal-2))))

;;; ── Run ────────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%Ledger examples: ~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
