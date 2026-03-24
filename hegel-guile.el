;;; hegel-guile.el --- Project support for hegel-guile development -*- lexical-binding: t; -*-

;; Author: dsp-dr
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (geiser "0.28") (geiser-guile "0.28"))
;; Keywords: lisp, scheme, guile, testing

;;; Commentary:

;; Development support for hegel-guile: a Hegel protocol client for GNU Guile 3.
;; Provides commands to run tests, start the hegel-core server, tangle the
;; literate source, and interact with Guile via Geiser.

;;; Code:

(require 'compile)

;;;; ── Project Paths ────────────────────────────────────────────────────────

(defvar hegel-guile-project-root
  (file-name-directory (or load-file-name buffer-file-name))
  "Root directory of the hegel-guile project.")

(defun hegel-guile--src-dir ()
  "Return the src/ directory path."
  (expand-file-name "src" hegel-guile-project-root))

(defun hegel-guile--test-dir ()
  "Return the tests/ directory path."
  (expand-file-name "tests" hegel-guile-project-root))

(defun hegel-guile--examples-dir ()
  "Return the examples/ directory path."
  (expand-file-name "examples" hegel-guile-project-root))

;;;; ── Guile / Geiser Integration ───────────────────────────────────────────

(defun hegel-guile-geiser-load-path ()
  "Add hegel-guile src/ to Geiser's load path."
  (interactive)
  (when (fboundp 'geiser-guile--parameters)
    (add-to-list 'geiser-guile-load-path (hegel-guile--src-dir)))
  (message "Added %s to Geiser load path" (hegel-guile--src-dir)))

;;;; ── Test Runner ──────────────────────────────────────────────────────────

(defun hegel-guile-run-cbor-tests ()
  "Run CBOR codec unit tests."
  (interactive)
  (compile (format "guile3 -L %s %s/test-cbor.scm"
                   (hegel-guile--src-dir)
                   (hegel-guile--test-dir))))

(defun hegel-guile-run-protocol-tests ()
  "Run protocol conjecture tests."
  (interactive)
  (compile (format "guile3 -L %s %s/test-protocol.scm"
                   (hegel-guile--src-dir)
                   (hegel-guile--test-dir))))

(defun hegel-guile-run-generator-tests ()
  "Run generator schema tests."
  (interactive)
  (compile (format "guile3 -L %s %s/test-generators.scm"
                   (hegel-guile--src-dir)
                   (hegel-guile--test-dir))))

(defun hegel-guile-run-all-tests ()
  "Run all offline unit tests (CBOR, protocol, generators)."
  (interactive)
  (compile (format "cd %s && gmake test" hegel-guile-project-root)))

(defun hegel-guile-run-test-file ()
  "Run the current test file with guile3."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless (and file (string-match-p "\\.scm\\'" file))
      (user-error "Not a .scm file"))
    (compile (format "guile3 -L %s %s" (hegel-guile--src-dir) file))))

;;;; ── Hegel Server ─────────────────────────────────────────────────────────

(defvar hegel-guile--server-process nil
  "Process object for the running hegel-core server.")

(defvar hegel-guile--server-socket nil
  "Path to the active hegel-core Unix socket.")

(defun hegel-guile-start-server ()
  "Start a hegel-core server subprocess.
The socket path is displayed in the *hegel-server* buffer."
  (interactive)
  (when (and hegel-guile--server-process
             (process-live-p hegel-guile--server-process))
    (user-error "Server already running (PID %d)"
                (process-id hegel-guile--server-process)))
  (let* ((socket-path (expand-file-name
                       (format "hegel-%d.sock" (emacs-pid))
                       temporary-file-directory))
         (buf (get-buffer-create "*hegel-server*"))
         (proc (start-process "hegel-core" buf
                              "uv" "run" "--directory" hegel-guile-project-root
                              "hegel" socket-path)))
    (setq hegel-guile--server-process proc
          hegel-guile--server-socket socket-path)
    (set-process-sentinel
     proc (lambda (p _event)
            (unless (process-live-p p)
              (setq hegel-guile--server-process nil)
              (message "hegel-core server stopped"))))
    (message "hegel-core started: %s" socket-path)))

(defun hegel-guile-stop-server ()
  "Stop the running hegel-core server."
  (interactive)
  (if (and hegel-guile--server-process
           (process-live-p hegel-guile--server-process))
      (progn
        (kill-process hegel-guile--server-process)
        (when (and hegel-guile--server-socket
                   (file-exists-p hegel-guile--server-socket))
          (delete-file hegel-guile--server-socket))
        (setq hegel-guile--server-process nil
              hegel-guile--server-socket nil)
        (message "hegel-core stopped"))
    (message "No server running")))

(defun hegel-guile-server-status ()
  "Display hegel-core server status."
  (interactive)
  (if (and hegel-guile--server-process
           (process-live-p hegel-guile--server-process))
      (message "hegel-core running (PID %d) socket: %s"
               (process-id hegel-guile--server-process)
               hegel-guile--server-socket)
    (message "hegel-core not running")))

;;;; ── Example Runner ───────────────────────────────────────────────────────

(defun hegel-guile-run-example (name)
  "Run an example by NAME (e.g., \"basic\", \"sicp\", \"ledger\")."
  (interactive
   (list (completing-read
          "Example: "
          (mapcar #'file-name-sans-extension
                  (directory-files (hegel-guile--examples-dir)
                                  nil "\\.scm\\'")))))
  (compile (format "guile3 -L %s %s/%s.scm"
                   (hegel-guile--src-dir)
                   (hegel-guile--examples-dir)
                   name)))

;;;; ── Tangle ───────────────────────────────────────────────────────────────

(defun hegel-guile-tangle ()
  "Tangle the literate source from hegel-guile.org."
  (interactive)
  (let ((org-file (expand-file-name "hegel-guile.org" hegel-guile-project-root)))
    (if (file-exists-p org-file)
        (compile (format "emacs --batch --eval \"(progn (require 'ob-tangle) (org-babel-tangle-file \\\"%s\\\"))\""
                         org-file))
      ;; Check tmp/ for the org file
      (let ((tmp-org (expand-file-name "tmp/hegel-guile.org" hegel-guile-project-root)))
        (if (file-exists-p tmp-org)
            (compile (format "emacs --batch --eval \"(progn (require 'ob-tangle) (org-babel-tangle-file \\\"%s\\\"))\""
                             tmp-org))
          (user-error "hegel-guile.org not found"))))))

;;;; ── Hypothesis / Python Side ─────────────────────────────────────────────

(defun hegel-guile-check-hypothesis ()
  "Check that hegel-core and hypothesis are installed."
  (interactive)
  (compile (format "cd %s && uv run hegel --version && uv run python -c 'import hypothesis; print(hypothesis.__version__)'"
                   hegel-guile-project-root)))

(defun hegel-guile-sync-deps ()
  "Run uv sync to install/update Python dependencies."
  (interactive)
  (compile (format "cd %s && uv sync" hegel-guile-project-root)))

;;;; ── Keymap ───────────────────────────────────────────────────────────────

(defvar hegel-guile-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "t") #'hegel-guile-run-all-tests)
    (define-key map (kbd "c") #'hegel-guile-run-cbor-tests)
    (define-key map (kbd "p") #'hegel-guile-run-protocol-tests)
    (define-key map (kbd "g") #'hegel-guile-run-generator-tests)
    (define-key map (kbd "f") #'hegel-guile-run-test-file)
    (define-key map (kbd "e") #'hegel-guile-run-example)
    (define-key map (kbd "s") #'hegel-guile-start-server)
    (define-key map (kbd "k") #'hegel-guile-stop-server)
    (define-key map (kbd "?") #'hegel-guile-server-status)
    (define-key map (kbd "T") #'hegel-guile-tangle)
    (define-key map (kbd "d") #'hegel-guile-sync-deps)
    (define-key map (kbd "h") #'hegel-guile-check-hypothesis)
    map)
  "Keymap for hegel-guile commands.
Bind to a prefix key, e.g.: (global-set-key (kbd \"C-c H\") hegel-guile-command-map)")

;;;; ── Dir-locals Integration ───────────────────────────────────────────────

;; When visiting .scm files in this project, ensure Geiser knows about src/
(dir-locals-set-class-variables
 'hegel-guile
 `((scheme-mode . ((eval . (progn
                             (setq-local geiser-guile-load-path
                                         (list ,(expand-file-name "src" hegel-guile-project-root)))
                             (setq-local compile-command
                                         ,(format "guile3 -L %s %s" (hegel-guile--src-dir) "%f"))))))))

(provide 'hegel-guile)

;;; hegel-guile.el ends here
