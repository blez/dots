#!/usr/bin/env bash
set -euo pipefail

if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "pavalk6@gmail.com"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519

    xclip -selection clipboard <~/.ssh/id_ed25519.pub
    read -n 1 -s -r -p "ssh key was copied. Add it to github. Press any key to continue"
fi

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
