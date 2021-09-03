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
(setq doom-font (font-spec :family "JetBrains Mono Medium" :size 27))
;;       doom-variable-pitch-font (font-spec :family "sans" :size 13))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
;; (setq doom-theme 'doom-dark+)
(setq doom-theme 'doom-dark+)
(setq fancy-splash-image "~/.emacs-e-logo.png")

(map! :n "R" #'evil-multiedit-match-all)
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
      :m "<f6>" #'flycheck-buffer)
(global-unset-key (kbd "<f3>"))
(map! :after flycheck
      :map lsp-mode-map
      :m "<f3>" #'lsp-workspace-restart)

(with-eval-after-load 'company
    (define-key company-active-map (kbd "<tab>") nil))

;; setup lsp + other linters
(add-hook! 'lsp-after-initialize-hook
  (run-hooks (intern (format "%s-lsp-hook" major-mode))))
(defun go-flycheck-setup ()
  (flycheck-add-next-checker 'lsp 'golangci-lint))
(add-hook 'go-mode-lsp-hook
          #'go-flycheck-setup)
(add-hook! lsp-mode
  (defalias '+lookup/references 'lsp-find-references))

(use-package! evil-multiedit
  :config
  (evil-multiedit-default-keybinds))
(use-package! makefile-executor
  :config
  (add-hook 'makefile-mode-hook 'makefile-executor-mode))
(use-package! olivetti
  :config
  (add-hook 'go-mode-hook #'olivetti-mode)
  (add-hook 'sh-mode-hook #'olivetti-mode)
  (add-hook 'yaml-mode-hook #'olivetti-mode)
  (add-hook 'rustic-mode-hook #'olivetti-mode))
(setq-hook! 'olivetti-mode-hook olivetti-body-width 150)
(after! undo-tree
  (setq undo-tree-auto-save-history nil))

(after! ivy-posframe
  (setf (alist-get t ivy-posframe-display-functions-alist)
        #'ivy-posframe-display-at-frame-center)
  (setf (alist-get 'swiper ivy-posframe-display-functions-alist)
        #'ivy-posframe-display-at-frame-center)
  (setq ivy-posframe-border-width 2
        ivy-posframe-parameters (append ivy-posframe-parameters '((left-fringe . 3)
                                                                  (right-fringe . 3)))))

;; (setq shfmt-arguments '("-bn" "-ci" "-s"))
(setq shfmt-arguments '("-s" "-i" "4" "-ln" "bash"))
(add-hook 'sh-mode-hook 'shfmt-on-save-mode)

(add-to-list 'auto-mode-alist '("Dockerfile\\'" . dockerfile-mode))
(add-to-list 'auto-mode-alist '("Jenkinsfile\\'" . groovy-mode))
(add-to-list 'auto-mode-alist '("Makefile.*" . makefile-mode))


(setq rustic-lsp-server 'rust-analyzer)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)
(add-hook 'protobuf-mode-hook #'display-line-numbers-mode)
(setq projectile-project-search-path '("~/go/src/github.com/blez/" "~/go/src/github.com/percona/" "~/go/src/github.com/Percona-Lab/"))
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
