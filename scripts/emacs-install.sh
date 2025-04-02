#!/usr/bin/env bash
set -euo pipefail

git clone git://git.savannah.gnu.org/emacs.git
(
    cd emacs
    git checkout emacs-30.1
    make clean
    ./autogen.sh
    ./configure --with-modules --with-native-compilation --without-pop --with-mailutils --with-sqlite3 --with-tree-sitter
    export LD_LIBRARY_PATH=/usr/local/lib/
    make bootstrap
    make -j$(nproc)
    sudo LD_LIBRARY_PATH=/usr/local/lib/ make install
)
