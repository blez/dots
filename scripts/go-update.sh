#!/usr/bin/env bash
set -euo pipefail

# filename=$(curl https://go.dev/dl/?mode=json | jq '.[0] .files' | jq -r '.[] | select(.os == "linux" and .arch == "amd64") | .filename')
filename=go1.21.4.linux-amd64.tar.gz
wget -O ~/Downloads/go.tar.gz "https://go.dev/dl/$filename"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf ~/Downloads/go.tar.gz
rm ~/Downloads/go.tar.gz
echo "go was updated to $(/usr/local/go/bin/go version)"
