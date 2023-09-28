#!/usr/bin/env bash
set -euo pipefail

url=$(curl https://api.github.com/repos/telegramdesktop/tdesktop/releases |
    jq -r 'first(.[] | .assets[] | select(.label == "Linux 64 bit: Binary")) | .browser_download_url')

wget -O ~/Downloads/telegram.tar.xz "$url"
tar -xf ~/Downloads/telegram.tar.xz -C ~/Downloads
sudo mv ~/Downloads/Telegram/* /usr/local/bin

rm ~/Downloads/telegram.tar.xz
rm -rf ~/Downloads/Telegram

version=$(awk -F '/' '{print $8}' <<< "$url")
echo "Telegram was updated to $version"
