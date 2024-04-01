#!/usr/bin/env bash
set -euo pipefail

git clone git://git.savannah.gnu.org/emacs.git
(
    cd emacs
    git checkout emacs-29.1
    make clean
    ./autogen.sh
    ./configure --with-modules --with-native-compilation --with-json --without-pop --with-mailutils --with-sqlite3
    make bootstrap
    make -j$(nproc)
    sudo make install
)
