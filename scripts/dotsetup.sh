#!/usr/bin/env bash
set -eu

if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "pavalk6@gmail.com"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519

    xclip -selection clipboard <~/.ssh/id_ed25519.pub
    read -n 1 -s -r -p "ssh key was copied. Add it to github. Press any key to continue"
fi
rm "$HOME/.gitignore"
echo "dots" > "$HOME/.gitignore"

rm -rf "$HOME/dots"
git clone --bare git@github.com:blez/dots.git "$HOME/dots"

function dots {
    /usr/bin/git --git-dir="$HOME/dots/" --work-tree="$HOME" "$@"
}

if dots checkout; then
    echo "Checked out config."
else
    mkdir -p ~/.config-backup
    echo "Removing up pre-existing dot files."
    dots checkout 2>&1 | grep -iEv "error|please|aborting" | awk '{print $1}' | xargs -I{} rm {}
fi

dots checkout
dots config status.showUntrackedFiles no
echo "Done"
