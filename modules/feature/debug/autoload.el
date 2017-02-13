;;; feature/debug/autoload.el

;;;###autoload
(defun +debug/quit ()
  (interactive)
  (ignore-errors (call-interactively 'realgud:cmd-quit))
  (doom/popup-close)
  (evil-normal-state))


;;;###autoload (autoload '+debug:debug-toggle-breakpoint "feature/debug/autoload" nil t)
;;;###autoload (autoload '+debug:run "feature/debug/autoload" nil t)

(@after evil
  (evil-define-command +debug:run (&optional path)
    "Initiate debugger for current major mode"
    (interactive "<f>")
    (let ((default-directory (doom-project-root)))
      (cond ((memq major-mode '(c-mode c++-mode))
             (realgud:gdb (if path (concat "gdb " path))))
            ((memq major-mode '(ruby-mode enh-ruby-mode))
             (doom:repl nil (format "run '%s'" (f-filename (or path buffer-file-name)))))
            ((eq major-mode 'sh-mode)
             (let ((shell sh-shell))
               (when (string= shell "sh")
                 (setq shell "bash"))
               (cond ((string= shell "bash")
                      (realgud:bashdb (if path (concat "bashdb " path))))
                     ((string= shell "zsh")
                      (realgud:zshdb (if path (concat "zshdb " path))))
                     (t (user-error "No shell debugger for %s" shell)))))
            ;; TODO Add python debugging
            ((memq major-mode '(js-mode js2-mode js3-mode))
             (realgud:trepanjs))
            ((eq major-mode 'haskell-mode)
             (haskell-debug))
            (t (user-error "No debugger for %s" major-mode)))))

  (evil-define-command +debug:debug-toggle-breakpoint (&optional bang)
    (interactive "<!>")
    (call-interactively (if bang 'realgud:cmd-clear 'realgud:cmd-break))))

