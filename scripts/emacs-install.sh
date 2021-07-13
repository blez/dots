#!/usr/bin/env bash
set -euo pipefail

git clone git://git.savannah.gnu.org/emacs.git
cd emacs
make clean
./autogen.sh
./configure --with-modules --with-native-compilation --with-json --without-pop --with-mailutils
# make bootstrap
make -j$(nproc)
make install
