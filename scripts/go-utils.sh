#!/usr/bin/env bash
set -euo pipefail

go install golang.org/x/tools/gopls@latest
go install github.com/fatih/gomodifytags@latest
go install github.com/cweill/gotests/gotests@latest
go install github.com/x-motemen/gore/cmd/gore@latest
go install github.com/stamblerre/gocode@latest
go install golang.org/x/tools/cmd/godoc@latest
go install golang.org/x/tools/cmd/goimports@latest
go install golang.org/x/tools/cmd/gorename@latest
go install golang.org/x/tools/cmd/guru@latest
