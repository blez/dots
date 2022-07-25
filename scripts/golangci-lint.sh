#!/usr/bin/env bash

set -euo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

VERSION=$(curl https://api.github.com/repos/golangci/golangci-lint/releases/latest | jq -r .tag_name)

wget -O ~/Downloads/lint.tar.gz --no-verbose \
    "https://github.com/golangci/golangci-lint/releases/download/${VERSION}/golangci-lint-${VERSION#v}-linux-amd64.tar.gz"
tar -xvzf ~/Downloads/lint.tar.gz -C ~/Downloads
sudo mv "$HOME/Downloads/golangci-lint-${VERSION#v}-linux-amd64/golangci-lint" /usr/local/bin
rm ~/Downloads/lint.tar.gz
echo "Done. $(golangci-lint --version)"
