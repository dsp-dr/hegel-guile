;;; examples/todo.scm — Todo list CRUD model-based testing
;;;
;;; A simple todo list with add/remove/toggle operations.
;;; We use model-based testing: run random operations on both the
;;; implementation and a trivial reference model, then compare.

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (hegel)
             (srfi srfi-1))

;;;; ── Todo List Implementation ─────────────────────────────────────────────

(define (make-todo-list) '())

(define (todo-add todos id title)
  "Add a todo item. Returns new list."
  (cons (list id title #f) todos))

(define (todo-remove todos id)
  "Remove item by ID. Returns new list."
  (filter (lambda (item) (not (= (car item) id))) todos))

(define (todo-toggle todos id)
  "Toggle done status of item ID. Returns new list."
  (map (lambda (item)
         (if (= (car item) id)
             (list (car item) (cadr item) (not (caddr item)))
             item))
       todos))

(define (todo-find todos id)
  "Find item by ID, or #f."
  (find (lambda (item) (= (car item) id)) todos))

(define (todo-count todos)
  (length todos))

(define (todo-done-count todos)
  (length (filter caddr todos)))

;;;; ── Property Tests ───────────────────────────────────────────────────────

(define-hegel-test (test-add-increases-count tc #:test-cases 300)
  "Adding an item increases count by 1."
  (let* ((id    (tc-draw tc (integers #:min-value 1 #:max-value 10000)))
         (todos (make-todo-list))
         (after (todo-add todos id "task")))
    (unless (= (todo-count after) (+ (todo-count todos) 1))
      (error "add did not increase count" id))))

(define-hegel-test (test-add-then-find tc #:test-cases 300)
  "After adding, the item is findable."
  (let* ((id    (tc-draw tc (integers #:min-value 1 #:max-value 10000)))
         (todos (todo-add (make-todo-list) id "my task"))
         (found (todo-find todos id)))
    (unless (and found (equal? (cadr found) "my task"))
      (error "could not find added item" id))))

(define-hegel-test (test-add-then-remove tc #:test-cases 300)
  "Adding then removing returns to empty."
  (let* ((id    (tc-draw tc (integers #:min-value 1 #:max-value 10000)))
         (todos (todo-add (make-todo-list) id "task"))
         (after (todo-remove todos id)))
    (unless (= (todo-count after) 0)
      (error "add then remove not empty" id))))

(define-hegel-test (test-toggle-idempotent tc #:test-cases 300)
  "Toggling twice restores original state."
  (let* ((id    (tc-draw tc (integers #:min-value 1 #:max-value 10000)))
         (todos (todo-add (make-todo-list) id "task"))
         (once  (todo-toggle todos id))
         (twice (todo-toggle once id))
         (orig  (todo-find todos id))
         (final (todo-find twice id)))
    (unless (equal? (caddr orig) (caddr final))
      (error "double toggle not idempotent" id))))

(define-hegel-test (test-toggle-flips-done tc #:test-cases 300)
  "Toggle changes done from #f to #t."
  (let* ((id    (tc-draw tc (integers #:min-value 1 #:max-value 10000)))
         (todos (todo-add (make-todo-list) id "task"))
         (after (todo-toggle todos id))
         (item  (todo-find after id)))
    (unless (eq? (caddr item) #t)
      (error "toggle did not set done" id))))

(define-hegel-test (test-remove-nonexistent-noop tc #:test-cases 200)
  "Removing a non-existent ID doesn't change the list."
  (let* ((id1   (tc-draw tc (integers #:min-value 1 #:max-value 5000)))
         (id2   (tc-draw tc (integers #:min-value 5001 #:max-value 10000)))
         (todos (todo-add (make-todo-list) id1 "task"))
         (after (todo-remove todos id2)))
    (unless (= (todo-count after) (todo-count todos))
      (error "removing nonexistent changed count" id1 id2))))

(define-hegel-test (test-model-random-operations tc #:test-cases 200)
  "Random sequence of add/remove/toggle ops: impl matches count model."
  (let* ((n-ops (tc-draw tc (integers #:min-value 1 #:max-value 20))))
    (let loop ((i 0) (todos (make-todo-list)) (model-ids '()))
      (if (= i n-ops)
          ;; Final check: count matches model
          (unless (= (todo-count todos) (length model-ids))
            (error "count mismatch" (todo-count todos) (length model-ids)))
          (let ((op (tc-draw tc (integers #:min-value 0 #:max-value 2)))
                (id (+ i 1)))  ; unique ID per step
            (cond
             ;; op 0: add
             ((= op 0)
              (loop (+ i 1)
                    (todo-add todos id "task")
                    (cons id model-ids)))
             ;; op 1: remove first if any
             ((and (= op 1) (not (null? model-ids)))
              (let ((rid (car model-ids)))
                (loop (+ i 1)
                      (todo-remove todos rid)
                      (delete rid model-ids))))
             ;; op 2 or remove on empty: toggle first if any
             ((not (null? model-ids))
              (loop (+ i 1)
                    (todo-toggle todos (car model-ids))
                    model-ids))
             ;; nothing to do, just add
             (else
              (loop (+ i 1)
                    (todo-add todos id "task")
                    (cons id model-ids)))))))))

;;; ── Run ────────────────────────────────────────────────────────────────────

(let ((failures (run-hegel-tests!)))
  (format #t "~%Todo app: ~a test(s) failed.~%" failures)
  (exit (if (= failures 0) 0 1)))
