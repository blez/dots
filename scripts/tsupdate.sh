#!/usr/bin/env bash
set -euo pipefail

tag=$(curl https://api.github.com/repos/telegramdesktop/tdesktop/releases/latest | jq -r .tag_name)
wget -O ~/Downloads/telegram.tar.xz "https://github.com/telegramdesktop/tdesktop/releases/download/${tag}/tsetup.${tag#v}.tar.xz"
tar -xf ~/Downloads/telegram.tar.xz -C ~/Downloads
sudo mv ~/Downloads/Telegram/* /usr/local/bin
rm ~/Downloads/telegram.tar.xz
rm -rf ~/Downloads/Telegram
echo "Telegram was updated"
