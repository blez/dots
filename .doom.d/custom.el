;;; -*- lexical-binding: t -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(safe-local-variable-values
      '((eval let*
            ((user (user-login-name)) (operator '("paval"))
                (backend '("john-doe"))
                (group
                    (cond ((member user operator) "operator")
                        ((member user backend) "backend") (t "unknown")))
                (ignored
                    (cond
                        ((string= group "operator")
                            '("[/\\\\]helios$" "[/\\\\]kubera$"))
                        ((string= group "backend")
                            '("[/\\\\]memsqloperator$" "[/\\\\]kubera$"))
                        (t
                            '("[/\\\\]helios$" "[/\\\\]kubera$"
                                 "[/\\\\]memsqloperator$")))))
            (message "[.dir-locals.el] User: %s | Group: %s | Ignored: %S" user
                group ignored)
            (setq-local lsp-file-watch-ignored-directories ignored))
           (eval let*
               ((user (user-login-name)) (operator (list user))
                   (backend '("john-doe"))
                   (group
                       (cond ((member user operator) "operator")
                           ((member user backend) "backend") (t "unknown")))
                   (ignored
                       (cond
                           ((string= group "operator")
                               '("[/\\\\]helios$" "[/\\\\]kubera$"))
                           ((string= group "backend")
                               '("[/\\\\]memsqloperator$" "[/\\\\]kubera$"))
                           (t
                               '("[/\\\\]helios$" "[/\\\\]kubera$"
                                    "[/\\\\]memsqloperator$")))))
               (message "[.dir-locals.el] User: %s | Group: %s | Ignored: %S"
                   user group ignored)
               (setq-local lsp-file-watch-ignored-directories ignored)))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
