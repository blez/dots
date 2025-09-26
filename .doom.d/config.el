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
(setq doom-font (font-spec :family "JetBrains Mono Nerd Font" :size 30))

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
(map! :leader
      (:prefix-map ("a" . "Custom")
       :desc "Save buffer" "a" #'save-buffer))
(map! :ie "C-h" #'backward-delete-char-untabify)
(map! :ie "C-d" #'delete-char)
(map! :n "C-e" #'doom/forward-to-last-non-comment-or-eol)

(after! dired
  (map! :map dired-mode-map
        :n "-" #'dired-do-kill-lines))

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
  (message "Setting up flycheck for Go")
  (flycheck-add-next-checker 'lsp 'golangci-lint))
(defun go-lsp-setup ()
  (setq lsp-go-build-flags ["-tags=operator,integration,cluster,debug"]))
;; (lsp-register-custom-settings '(("gopls.buildFlags" ["-tags=operator,integration,cluster,debug"]))))
(add-hook! '(go-mode-lsp-hook go-ts-mode-lsp-hook) #'go-flycheck-setup #'go-lsp-setup)

(add-hook! '(sh-mode-lsp-hook sh-ts-mode-lsp-hook) #'sh-flycheck-setup)
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
  (add-hook! '(
               go-mode-hook go-ts-mode-hook
               sh-mode-hook sh-ts-mode-hook
               dart-mode-hook dart-ts-mode-hook
               yaml-mode-hook yaml-ts-mode-hook
               org-mode-hook org-ts-mode-hook
               rustic-mode-hook rustic-ts-mode-hook
               python-mode-hook python-ts-mode-hook
               emacs-lisp-mode-hook
               ) #'olivetti-mode))
(setq-hook! 'olivetti-mode-hook olivetti-body-width 150)

(use-package! dap-dlv-go
  :after (go-mode dap-mode)
  :config
  (dap-register-debug-template "Remote Debug Go"
                               (list :type "go"
                                     :request "attach"
                                     :mode "remote"
                                     :name "Remote Debug Go"
                                     :host "0.0.0.0"
                                     :port 2345
                                     :program "${workspaceFolder}")))

(use-package! dap-mode
  :after lsp-mode
  :config
  (dap-mode 1)
  (dap-ui-mode 1)
  (dap-auto-configure-mode -1)
  (dap-ui-controls-mode -1)
  (dap-tooltip-mode -1)
  (tooltip-mode -1)
  (setq dap-auto-configure-features '())
  (set-popup-rule! "^\\*Remote Debug Go.*" :ignore t)
  (set-popup-rule! "^\\*Dlv Remote Debug" :ignore t)
  ;; (set-popup-rule! "*Launch File" :size 0.2 :slot -4 :select t :quit t :ttl 0 :side 'bottom)
  (set-popup-rule! "^\\*dap-ui-locals\\*" :side 'bottom)
  (remove-hook 'dap-mode-hook #'dap-ui-mode)
  (remove-hook 'dap-mode-hook #'dap-ui-controls-mode)
  (add-hook 'dap-stopped-hook
            (lambda (arg)
              (interactive)
              (dap-hydra)
              ))
  )

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
;; (set-formatter! 'yamlfmt
;;   '("yamlfmt" "-in" "-formatter" "indent=4,indentless_arrays=true,retain_line_breaks=true") :modes '(yaml-mode))
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
            (let ((root (projectile-project-root)))
              (message "Current project root: %s" root)
              (cond
               ((string-prefix-p "/home/pkasko-ua/helios/singlestore.com/helios/" root)
                (message "Renaming perspective to 'backend'")
                (persp-rename "backend"))
               ((string-prefix-p "/home/pkasko-ua/helios/singlestore.com/" root)
                (message "Renaming perspective to 'operator'")
                (persp-rename "operator"))))))

(setq auth-sources '("~/.authinfo"))
(setq gptel-api-key (auth-source-pick-first-password :host "api.openai.com"))
(map! :leader
      :prefix "a"
      :desc "GPTel" "i" #'gptel
      :desc "GPTel send" "s" #'gptel-send
      :desc "GPTel Menu" "m" #'gptel-menu)

(use-package aidermacs
  :config
  (setenv "ANTHROPIC_API_KEY" (auth-source-pick-first-password :host "api.anthropic.com"))
  (setenv "OPENAI_API_KEY" (auth-source-pick-first-password :host "api.openai.com"))
  :custom
  (aidermacs-use-architect-mode t)
  (aidermacs-default-model "sonnet"))

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
