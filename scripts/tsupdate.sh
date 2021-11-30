#!/usr/bin/env bash
set -euo pipefail

wget -O ~/Downloads/telegram.tar.xz https://telegram.org/dl/desktop/linux
tar -xf ~/Downloads/telegram.tar.xz -C ~/Downloads
sudo mv ~/Downloads/Telegram/* /usr/local/bin
rm ~/Downloads/telegram.tar.xz
rm -rf ~/Downloads/Telegram
echo "Telegram was updated"
