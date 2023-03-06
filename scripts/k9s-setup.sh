#!/usr/bin/env bash
set -euo pipefail

tag=$(curl https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
wget -O ~/Downloads/k9s.tar.gz "https://github.com/derailed/k9s/releases/download/${tag}/k9s_Linux_amd64.tar.gz"
tar -xzf ~/Downloads/k9s.tar.gz -C ~/Downloads
sudo mv ~/Downloads/k9s /usr/local/bin
rm ~/Downloads/k9s.tar.gz
echo "k9s was updated"
