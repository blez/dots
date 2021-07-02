#!/usr/bin/env bash
set -euo pipefail

git clone git://git.savannah.gnu.org/emacs.git -b feature/native-comp
cd emacs
make clean
./autogen.sh
./configure --with-modules --with-native-compilation --with-json --without-pop --with-mailutils
make -j$(nproc)
make install
