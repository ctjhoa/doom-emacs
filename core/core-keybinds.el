;;; core-keybinds.el -*- lexical-binding: t; -*-

;; A centralized keybinds system, integrated with `which-key' to preview
;; available keybindings. All built into one powerful macro: `map!'. If evil is
;; never loaded, then evil bindings set with `map!' will be ignored.

(defvar doom-leader-key "SPC"
  "The leader prefix key for Evil users.")

(defvar doom-leader-alt-key "M-SPC"
  "An alternative leader prefix key, used for Insert and Emacs states, and for
non-evil users.")

(defvar doom-localleader-key "SPC m"
  "The localleader prefix key, for major-mode specific commands.")

(defvar doom-localleader-alt-key "M-SPC m"
  "The localleader prefix key, for major-mode specific commands.")

(defvar doom-leader-map (make-sparse-keymap)
  "An overriding keymap for <leader> keys.")


;;
(defvar doom-escape-hook nil
  "A hook run after C-g is pressed (or ESC in normal mode, for evil users). Both
trigger `doom/escape'.

If any hook returns non-nil, all hooks after it are ignored.")

(defun doom/escape ()
  "Run the `doom-escape-hook'."
  (interactive)
  (cond ((minibuffer-window-active-p (minibuffer-window))
         ;; quit the minibuffer if open.
         (abort-recursive-edit))
        ;; Run all escape hooks. If any returns non-nil, then stop there.
        ((cl-find-if #'funcall doom-escape-hook))
        ;; don't abort macros
        ((or defining-kbd-macro executing-kbd-macro) nil)
        ;; Back to the default
        ((keyboard-quit))))

(global-set-key [remap keyboard-quit] #'doom/escape)


;;
;; General

(require 'general)

;; Convenience aliases
(defalias 'define-key! #'general-def)
(defalias 'unmap! #'general-unbind)

;; <leader>
(define-prefix-command 'doom-leader 'doom-leader-map)
(define-key doom-leader-map [override-state] 'all)
(general-define-key :states '(normal visual motion replace) doom-leader-key 'doom-leader)
(general-define-key :states '(emacs insert) doom-leader-alt-key 'doom-leader)

(general-create-definer define-leader-key!
  :wk-full-keys nil
  :keymaps 'doom-leader-map)

;; <localleader>
(general-create-definer define-localleader-key!
  :major-modes t
  :keymaps 'local
  :prefix doom-localleader-alt-key)

;; Because :non-normal-prefix doesn't work for non-evil sessions (only evil's
;; emacs state), we must redefine `define-localleader-key!' once evil is loaded
(after! evil
  (general-create-definer define-localleader-key!
    :major-modes t
    :keymaps 'local
    :prefix doom-localleader-key
    :non-normal-prefix doom-localleader-alt-key))


;;
;; Packages

(def-package! which-key
  :defer 1
  :after-call pre-command-hook
  :init
  (setq which-key-sort-order #'which-key-prefix-then-key-order
        which-key-sort-uppercase-first nil
        which-key-add-column-padding 1
        which-key-max-display-columns nil
        which-key-min-display-lines 6
        which-key-side-window-slot -10)
  :config
  ;; general improvements to which-key readability
  (set-face-attribute 'which-key-local-map-description-face nil :weight 'bold)
  (which-key-setup-side-window-bottom)
  (setq-hook! 'which-key-init-buffer-hook line-spacing 3)
  (which-key-mode +1))


;; `hydra'
(setq lv-use-seperator t)


;;
(defvar doom-evil-state-alist
  '((?n . normal)
    (?v . visual)
    (?i . insert)
    (?e . emacs)
    (?o . operator)
    (?m . motion)
    (?r . replace)
    (?g . global))
  "A list of cons cells that map a letter to a evil state symbol.")

(defun doom--keyword-to-states (keyword)
  "Convert a KEYWORD into a list of evil state symbols.

For example, :nvi will map to (list 'normal 'visual 'insert). See
`doom-evil-state-alist' to customize this."
  (cl-loop for l across (substring (symbol-name keyword) 1)
           if (cdr (assq l doom-evil-state-alist)) collect it
           else do (error "not a valid state: %s" l)))


;; Register keywords for proper indentation (see `map!')
(put :after        'lisp-indent-function 'defun)
(put :desc         'lisp-indent-function 'defun)
(put :leader       'lisp-indent-function 'defun)
(put :localleader  'lisp-indent-function 'defun)
(put :map          'lisp-indent-function 'defun)
(put :keymap       'lisp-indent-function 'defun)
(put :mode         'lisp-indent-function 'defun)
(put :prefix       'lisp-indent-function 'defun)
(put :alt-prefix   'lisp-indent-function 'defun)
(put :unless       'lisp-indent-function 'defun)
(put :if           'lisp-indent-function 'defun)
(put :when         'lisp-indent-function 'defun)

;; specials
(defvar doom--map-forms nil)
(defvar doom--map-fn 'general-define-key)
(defvar doom--map-batch-forms nil)
(defvar doom--map-state '(:dummy t))
(defvar doom--map-parent-state nil)
(defvar doom--map-evil-p nil)
(after! evil (setq doom--map-evil-p t))

(defun doom--map-process (rest)
  (let ((doom--map-fn doom--map-fn)
        doom--map-state
        doom--map-forms
        desc)
    (while rest
      (let ((key (pop rest)))
        (cond ((listp key)
               (doom--map-nested nil key))

              ((keywordp key)
               (pcase key
                 (:leader
                  (setq doom--map-fn 'define-leader-key!))
                 (:localleader
                  (setq doom--map-fn 'define-localleader-key!))
                 (:after
                  (doom--map-nested (list 'after! (pop rest)) rest)
                  (setq rest nil))
                 (:desc
                  (setq desc (pop rest)))
                 ((or :map :map* :keymap)
                  (doom--map-set :keymaps `(quote ,(doom-enlist (pop rest)))))
                 (:mode
                  (push (cl-loop for m in (doom-enlist (pop rest))
                                 collect (intern (concat (symbol-name m) "-map")))
                        rest)
                  (push :map rest))
                 ((or :if :when :unless)
                  (doom--map-nested (list (intern (doom-keyword-name key)) (pop rest)) rest)
                  (setq rest nil))
                 (:prefix
                  (cl-destructuring-bind (prefix . desc) (doom-enlist (pop rest))
                    (doom--map-set :prefix prefix)
                    (when (stringp desc)
                      (setq rest (append (list :desc desc "" nil) rest)))))
                 (:alt-prefix
                  (cl-destructuring-bind (prefix . desc) (doom-enlist (pop rest))
                    (doom--map-set :non-normal-prefix prefix)
                    (when (stringp desc)
                      (setq rest (append (list :desc desc "" nil) rest)))))
                 (:textobj
                  (let* ((key (pop rest))
                         (inner (pop rest))
                         (outer (pop rest)))
                    (push `(map! (:map evil-inner-text-objects-map ,key ,inner)
                                 (:map evil-outer-text-objects-map ,key ,outer))
                          doom--map-forms)))
                 (_
                  (condition-case e
                      (doom--map-def (pop rest) (pop rest) (doom--keyword-to-states key) desc)
                    (error
                     (error "Not a valid `map!' property: %s" key))))))

              ((doom--map-def key (pop rest) nil desc)))))

    (doom--map-commit)
    (macroexp-progn (nreverse (delq nil doom--map-forms)))))

(defun doom--map-append-keys (prop)
  (let ((a (plist-get doom--map-parent-state prop))
        (b (plist-get doom--map-state prop)))
    (if (and a b)
        `(general--concat t ,a ,b)
      (or a b))))

(defun doom--map-nested (wrapper rest)
  (doom--map-commit)
  (let ((doom--map-parent-state (copy-seq (append doom--map-state doom--map-parent-state nil))))
    (push (if wrapper
              (append wrapper (list (doom--map-process rest)))
            (doom--map-process rest))
          doom--map-forms)))

(defun doom--map-set (prop &optional value inhibit-commit)
  (unless (or inhibit-commit
              (equal (plist-get doom--map-state prop) value))
    (doom--map-commit))
  (setq doom--map-state (plist-put doom--map-state prop value)))

(defun doom--map-def (key def &optional states desc)
  (when (or (memq 'global states) (null states))
    (setq states (delq 'global states))
    (push 'nil states))
  (if (and (listp def)
           (memq (car-safe (doom-unquote def)) '(:def :ignore :keymap)))
      (setq def `(quote ,(plist-put (general--normalize-extended-def (doom-unquote def))
                                    :which-key desc)))
    (when desc
      (setq def `(list ,@(cond ((and (equal key "")
                                     (null def))
                                `(nil :which-key ,desc))
                               ((plist-put (general--normalize-extended-def def)
                                           :which-key desc)))))))
  (dolist (state states)
    (push key (alist-get state doom--map-batch-forms))
    (push def (alist-get state doom--map-batch-forms))))

(defun doom--map-commit ()
  (when doom--map-batch-forms
    (cl-loop with attrs = (doom--map-state)
             for (state . defs) in doom--map-batch-forms
             if (or doom--map-evil-p (not state))
             collect `(,doom--map-fn ,@(if state `(:states ',state)) ,@attrs ,@(nreverse defs))
             into forms
             finally do (push (macroexp-progn forms) doom--map-forms))
    (setq doom--map-batch-forms nil)))

(defun doom--map-state ()
  (let ((plist
         (append (list :prefix (doom--map-append-keys :prefix)
                       :non-normal-prefix (doom--map-append-keys :non-normal-prefix)
                       :keymaps
                       (append (plist-get doom--map-parent-state :keymaps)
                               (plist-get doom--map-state :keymaps)
                               nil))
                 doom--map-state
                 nil))
        newplist)
    (while plist
      (let ((key (pop plist))
            (val (pop plist)))
        (when (and val (not (plist-member newplist key)))
          (push val newplist)
          (push key newplist))))
    newplist))

;;
(defmacro map! (&rest rest)
  "A convenience macro for defining keybinds, powered by `general'.

If evil isn't loaded, evil-specific bindings are ignored.

States
  :n  normal
  :v  visual
  :i  insert
  :e  emacs
  :o  operator
  :m  motion
  :r  replace
  :g  global  (will work without evil)

  These can be combined in any order, e.g. :nvi will apply to normal, visual and
  insert mode. The state resets after the following key=>def pair. If states are
  omitted the keybind will be global (no emacs state; this is different from
  evil's Emacs state and will work in the absence of `evil-mode').

Properties
  :leader [...]                   an alias for (:prefix doom-leader-key ...)
  :localleader [...]              bind to localleader; requires a keymap
  :mode [MODE(s)] [...]           inner keybinds are applied to major MODE(s)
  :map [KEYMAP(s)] [...]          inner keybinds are applied to KEYMAP(S)
  :keymap [KEYMAP(s)] [...]       same as :map
  :prefix [PREFIX] [...]          set keybind prefix for following keys
  :alt-prefix [PREFIX] [...]      use non-normal-prefix for following keys
  :after [FEATURE] [...]          apply keybinds when [FEATURE] loads
  :textobj KEY INNER-FN OUTER-FN  define a text object keybind pair
  :if [CONDITION] [...]
  :when [CONDITION] [...]
  :unless [CONDITION] [...]

  Any of the above properties may be nested, so that they only apply to a
  certain group of keybinds.

Example
  (map! :map magit-mode-map
        :m  \"C-r\" 'do-something           ; C-r in motion state
        :nv \"q\" 'magit-mode-quit-window   ; q in normal+visual states
        \"C-x C-r\" 'a-global-keybind
        :g \"C-x C-r\" 'another-global-keybind  ; same as above

        (:when IS-MAC
         :n \"M-s\" 'some-fn
         :i \"M-o\" (lambda (interactive) (message \"Hi\"))))"
  (doom--map-process rest))

(provide 'core-keybinds)
;;; core-keybinds.el ends here
