#!/bin/bash
set -euo pipefail

git clone --bare git@github.com:blez/dots.git "$HOME/dots"

alias dots='git --git-dir=$HOME/dots/ --work-tree=$HOME'

if ! dots checkout; then
    echo "Checked out config."
else
    mkdir -p ~/.config-backup
    echo "Backing up pre-existing dot files."
    dots checkout 2>&1 | grep -E "\\s+\\." | awk '{print $1}' | xargs -I{} mv {} ~/.config-backup/{}
fi

dots checkout
dots config status.showUntrackedFiles no
