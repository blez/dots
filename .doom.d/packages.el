;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

(package! go-fill-struct)
(package! evil-easymotion)
(package! evil-snipe)
(package! evil-commentary)
(package! evil-indent-plus)
(package! evil-surround)
(package! protobuf-mode)
(package! makefile-executor)
(package! dockerfile-mode)
(package! browse-at-remote)
(package! groovy-mode)
;; (package! shfmt)
(package! string-inflection)
(package! centered-window)
(package! olivetti)
(package! beacon)
(package! exec-path-from-shell)
(package! transient
      :pin "c2bdf7e12c530eb85476d3aef317eb2941ab9440"
      :recipe (:host github :repo "magit/transient"))

(package! with-editor
          :pin "bbc60f68ac190f02da8a100b6fb67cf1c27c53ab"
          :recipe (:host github :repo "magit/with-editor"))
