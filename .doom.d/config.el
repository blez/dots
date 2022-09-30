;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "blez"
      user-mail-address "pavalk6@gmail.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
;; (setq doom-font (font-spec :family "JetBrains Mono Medium" :size 20))
(setq doom-font (font-spec :family "JetBrains Mono Nerd Font" :size 25))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
;; (setq doom-theme 'doom-dark+)
(setq doom-theme 'modus-vivendi)
;; (setq modus-themes-syntax '(faint))

(setq fancy-splash-image "~/.emacs-e-logo.png")

(map! :after neotree
      :map neotree-mode-map
      :m "h" #'+neotree/collapse-or-up)
(map! :after neotree
      :map neotree-mode-map
      :m "l" #'+neotree/expand-or-open)
(map! :i "M-p" #'yank)
(map! :i "C-j" #'next-line)
(map! :i "C-k" #'previous-line)
(map! :n "<f5>" #'call-last-kbd-macro)
(map! :after flycheck
      :map flycheck-mode-map
      :m "<f12>" #'flycheck-next-error)
(map! :after flycheck
      :map flycheck-mode-map
      :m "<f9>" #'flycheck-previous-error)
(map! :after flycheck
      :map flycheck-mode-map
      :m "<f11>" #'lsp-ui-flycheck-list)
(map! :after flycheck
      :map flycheck-mode-map
      :m "<f6>" #'flycheck-buffer)
(map! :map lsp-mode-map
      :m "<f7>" #'lsp-ui-doc-show)
(eval-after-load 'smerge-mode
  (lambda ()
    (define-key smerge-mode-map (kbd "C-,") smerge-basic-map)))

(global-unset-key (kbd "<f3>"))
(map! :m "<f3>" #'lsp-workspace-restart)

(map! :n "J" #'evil-mc-make-cursor-move-next-line)
(map! :n "K" #'evil-mc-make-cursor-move-prev-line)

(defun current-line-empty-p ()
  (save-excursion
    (beginning-of-line)
    (looking-at-p "[[:space:]]*$")))
(defun move-previous-line ()
  (interactive)
  (forward-line -1)
  (if (current-line-empty-p)
      (kill-line)))
(defun move-next-line ()
  (interactive)
  (beginning-of-line)
  (+evil/insert-newline-above 1)
  (forward-line 1))

(map! :m "C-j" #'move-next-line)
(map! :m "C-k" #'move-previous-line)

(map! :m "C-M-j" #'evil-scroll-line-down)
(map! :m "C-M-k" #'evil-scroll-line-up)

(map! :m "M-K" #'drag-stuff-up)
(map! :m "M-J" #'drag-stuff-down)

(defun previous-func ()
  (interactive)
  (end-of-defun)
  (end-of-defun)
  (beginning-of-defun))
(map! :m "M-j" #'previous-func)
(map! :m "M-k" #'beginning-of-defun)

(with-eval-after-load 'company
  (define-key company-active-map (kbd "<tab>") nil))

;; setup lsp + other linters
(setenv "GOPATH" "/home/pkasko-ua/go/") ;; TMP
(add-hook! 'lsp-after-initialize-hook
  (run-hooks (intern (format "%s-lsp-hook" major-mode))))
(defun go-flycheck-setup ()
  (flycheck-add-next-checker 'lsp 'golangci-lint))
(defun go-lsp-setup ()
  (lsp-register-custom-settings '(("gopls.buildFlags" ["-tags=operator,integration,cluster,debug"]))))
(add-hook 'go-mode-lsp-hook #'go-flycheck-setup)
(add-hook 'go-mode-lsp-hook #'go-lsp-setup)

(add-hook 'sh-mode-lsp-hook #'sh-flycheck-setup)
(defun sh-flycheck-setup ()
  (flycheck-add-next-checker 'lsp 'sh-bash 'sh-shellcheck))

(add-hook! lsp-mode
  (defalias '+lookup/references 'lsp-find-references))

(use-package! makefile-executor
  :config
  (add-hook 'makefile-mode-hook 'makefile-executor-mode))
(use-package! olivetti
  :config
  (add-hook 'go-mode-hook #'olivetti-mode)
  (add-hook 'sh-mode-hook #'olivetti-mode)
  (add-hook 'yaml-mode-hook #'olivetti-mode)
  (add-hook 'org-mode-hook #'olivetti-mode)
  (add-hook 'rustic-mode-hook #'olivetti-mode)
  (add-hook 'emacs-lisp-mode-hook #'olivetti-mode))
(setq-hook! 'olivetti-mode-hook olivetti-body-width 150)

(beacon-mode 1)

;; (use-package! minimap
;;     :config
;;     (setq minimap-window-location 'left))

(after! undo-tree
  (setq undo-tree-auto-save-history nil))

;; (after! ivy-posframe
;;   (setf (alist-get t ivy-posframe-display-functions-alist)
;;         #'ivy-posframe-display-at-frame-center)
;;   (setf (alist-get 'swiper ivy-posframe-display-functions-alist)
;;         #'ivy-posframe-display-at-frame-bottom-center)
;;   (setq ivy-posframe-border-width 6
;;         ivy-posframe-parameters (append ivy-posframe-parameters '((left-fringe . 3)
;;                                                                   (right-fringe . 3)))))

(put '+format-with 'safe-local-variable 'symbolp)
;; (setq shfmt-arguments '("-s" "-i" "4" "-ln" "bash"))
;; (add-hook 'sh-mode-hook 'shfmt-on-save-mode)

(add-to-list 'auto-mode-alist '("Dockerfile\\'" . dockerfile-mode))
(add-to-list 'auto-mode-alist '("Jenkinsfile\\'" . groovy-mode))
(add-to-list 'auto-mode-alist '("Makefile.*" . makefile-mode))
(add-to-list '+format-on-save-enabled-modes 'yaml-mode 'append)

(setq rustic-lsp-server 'rust-analyzer)

(exec-path-from-shell-copy-env "SSH_AGENT_PID")
(exec-path-from-shell-copy-env "SSH_AUTH_SOCK")

(setq org-clock-sound "~/sounds/bell.wav")

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")
(setq org-roam-directory "~/blez/roam/")

;; (add-to-list 'load-path "/usr/share/emacs/site-lisp/mu4e")
;; (after! mu4e
;;     (set-email-account! "pavalk6@gmail.com" '(
;;              (mu4e-sent-folder       . "/[Gmail]/Sent Mail")
;;              (mu4e-drafts-folder     . "/[Gmail]/Drafts")
;;              (mu4e-trash-folder      . "/[Gmail]/Trash")
;;              (mu4e-refile-folder     . "/[Gmail]/All Mail")
;;              (smtpmail-smtp-user     . "pavalk6@gmail.com"))
;;         t)

;;   (setq send-mail-function #'smtpmail-send-it
;;       mu4e-change-filenames-when-moving t
;;       mu4e-root-maildir "~/Mail"
;;       message-sendmail-f-is-evil t
;;       mu4e-update-interval 300
;;       mu4e-get-mail-command "mbsync -c ~/.config/mu4e/mbsyncrc -a"
;;       ;; don't need to run cleanup after indexing for gmail
;;       mu4e-index-cleanup nil
;;       ;; because gmail uses labels as folders we can use lazy check since
;;       ;; messages don't really "move"
;;       mu4e-index-lazy-check t
;;       mu4e-maildir-shortcuts '(
;;         ("/Inbox"             . ?i)
;;         ("/[Gmail]/Sent Mail" . ?s)
;;         ("/[Gmail]/Trash"     . ?t)
;;         ("/[Gmail]/Drafts"    . ?d)
;;         ("/[Gmail]/All Mail"  . ?a))
;;       )
;; )

;; (setq mu4e-alert-interesting-mail-query
;;     (concat "flag:unread maildir:/Inbox" ))

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)
(add-hook 'protobuf-mode-hook #'display-line-numbers-mode)
;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
