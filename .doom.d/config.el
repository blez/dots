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
;; (setq doom-font (font-spec :family "JetBrains Mono Nerd Font" :size 23))
(setq doom-font (font-spec :family "JetBrains Mono Nerd Font" :size 33))

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
      :m "<f11>" #'flycheck-list-errors)
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

(map! :leader :desc "Transpose frame" "w /" #'transpose-frame)
(map! :leader :desc "Save buffer" "a a" #'save-buffer)
(map! :ie "C-h" #'backward-delete-char-untabify)
(map! :ie "C-d" #'delete-char)
(map! :n "C-e" #'doom/forward-to-last-non-comment-or-eol)

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

(use-package! drag-stuff
  :defer t
  :init
  (map! "M-K"    #'drag-stuff-up
        "M-J"  #'drag-stuff-down
        "M-H"  #'drag-stuff-left
        "M-L" #'drag-stuff-right))

(defun previous-func ()
  (interactive)
  (end-of-defun)
  (end-of-defun)
  (beginning-of-defun))
(map! :m "M-j" #'previous-func)
(map! :m "M-k" #'beginning-of-defun)
(map! :n "," #'evil-first-non-blank)
(map! :n "." #'evil-end-of-line)

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

(add-hook! 'c-mode-hook
  (if (equal "keymap.c" (file-name-nondirectory buffer-file-name))
      (setq +format-with :none)))

(use-package! makefile-executor
  :config
  (add-hook 'makefile-mode-hook 'makefile-executor-mode))

(use-package! olivetti
  :config
  (add-hook 'go-mode-hook #'olivetti-mode)
  (add-hook 'sh-mode-hook #'olivetti-mode)
  (add-hook 'dart-mode-hook #'olivetti-mode)
  (add-hook 'yaml-mode-hook #'olivetti-mode)
  (add-hook 'org-mode-hook #'olivetti-mode)
  (add-hook 'rustic-mode-hook #'olivetti-mode)
  (add-hook 'python-mode-hook #'olivetti-mode)
  (add-hook 'emacs-lisp-mode-hook #'olivetti-mode))
(setq-hook! 'olivetti-mode-hook olivetti-body-width 150)

;; (use-package! dap-mode
;;   (setq dap-auto-configure-features '(sessions locals))
;;   (setq dap-ui-mode nil)
;;   (setq dap-ui-controls-mode nil)
;;   (setq dap-tooltip-mode nil)
;;   (setq tooltip-mode nil)
;;   (set-popup-rule! "^\\*Dlv Remote Debug" :ignore t)
;;   (set-popup-rule! "*Launch File" :size 0.2 :slot -4 :select t :quit t :ttl 0 :side 'bottom))

;; (remove-hook 'dap-mode-hook #'dap-ui-mode)
;; (remove-hook 'dap-mode-hook #'dap-ui-controls-mode)
;; (remove-hook 'dap-mode-hook #'dap-tooltip-mode)

(use-package! dap-mode
  :custom
  (dap-ui-mode nil)
  (dap-ui-controls-mode nil)
  (dap-tooltip-mode nil)
  (tooltip-mode nil)
  (dap-auto-configure-features '(sessions locals))
  :config
  (set-popup-rule! "*Launch File" :size 0.2 :slot -4 :select t :quit t :ttl 0 :side 'bottom)
  (set-popup-rule! "^\\*Dlv Remote Debug" :ignore t)
  )

;; (after! dap-mode
;;   (setq dap-ui-mode nil)
;;   (setq dap-ui-controls-mode nil)
;;   (setq dap-tooltip-mode nil)
;;   (setq tooltip-mode nil)
;;   (setq dap-auto-configure-features '(sessions locals))
;;   (set-popup-rule! "^\\*Dlv Remote Debug" :ignore t)
;;   (set-popup-rule! "*Launch File" :size 0.2 :slot -4 :select t :quit t :ttl 0 :side 'bottom))


(setq-hook! 'rjsx-mode-hook +format-with-lsp nil)

(setq lsp-grammarly-server-path "~/.local/share/pnpm/grammarly-languageserver")
(use-package lsp-grammarly
  :ensure t
  :hook (text-mode . (lambda ()
                       (require 'lsp-grammarly)
                       (lsp))))
(beacon-mode 1)

(use-package! copilot
  :hook (prog-mode . copilot-mode)
  :bind (:map copilot-completion-map
              ("C-e" . 'copilot-accept-completion)
              ("M-e" . 'copilot-accept-completion-by-word)
              ("C-n" . 'copilot-next-completion)
              ("C-p" . 'copilot-previous-completion))
  :config
  (add-to-list 'copilot-indentation-alist '(go-mode 2)))

(put '+format-with 'safe-local-variable 'symbolp)
;; (set-formatter! 'shfmt '("shfmt", "-s" "-i" "4" "-ln" "bash") :modes '(sh-mode))
(set-formatter! 'yamlfmt
  '("yamlfmt" "-in" "-formatter" "indent=2,indentless_arrays=true,retain_line_breaks=true") :modes '(yaml-mode))
(set-formatter! 'dockfmt '("dockfmt" "version") :modes '(dockerfile-mode))
(set-formatter! 'rustfmt '("rustfmt" "--edition" "2021") :modes '(rustic-mode))

(add-to-list 'auto-mode-alist '("Dockerfile\\'" . dockerfile-mode))
(add-to-list 'auto-mode-alist '("Jenkinsfile\\'" . groovy-mode))
(add-to-list 'auto-mode-alist '("Makefile.*" . makefile-mode))

(setq rustic-lsp-server 'rust-analyzer)

(exec-path-from-shell-copy-env "SSH_AGENT_PID")
(exec-path-from-shell-copy-env "SSH_AUTH_SOCK")

(setq org-clock-sound "~/sounds/bell.wav")
(setq org-hide-emphasis-markers t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")
(setq org-roam-directory "~/blez/roam/")

(add-hook 'projectile-after-switch-project-hook
          (lambda ()
            (message "Current project root: %s" (projectile-project-root))
            (when (string-prefix-p "/home/pkasko-ua/helios/singlestore.com/helios/" (projectile-project-root))
              (message "Renaming perspective to 'freya'")
              (persp-rename "freya")
              (message "Renaming done"))))
(after! projectile (setq projectile-project-root-files-bottom-up (remove ".git" projectile-project-root-files-bottom-up)))

(setq auth-sources '("~/.authinfo"))
(setq gptel-api-key (auth-source-pick-first-password :host "api.openai.com"))
(map! :leader
      :prefix "a"
      :desc "GPTel" "i" #'gptel
      :desc "GPTel send" "s" #'gptel-send
      :desc "GPTel Menu" "m" #'gptel-menu)

(global-disable-mouse-mode)
(setq disable-mouse-global-mode t)
(mapc #'disable-mouse-in-keymap
      (list evil-motion-state-map
            evil-normal-state-map
            evil-visual-state-map
            evil-insert-state-map))

(setq erc-server "irc.libera.chat"
      erc-nick "blez"
      erc-user-full-name "blez"
      erc-track-shorten-start 8
      erc-autojoin-channels-alist '(("irc.libera.chat" "#systemcrafters"))
      erc-kill-buffer-on-part t
      erc-auto-query 'bury)

;; (add-hook 'code-review-mode-hook
;;           (lambda ()
;;             (persp-add-buffer (current-buffer))))

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
