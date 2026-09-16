#!/usr/bin/env bash
set -eu

if [ ! -f ~/.ssh/id_ed25519 ]; then
    sudo apt install xclip
    ssh-keygen -t ed25519 -C "pavalk6@gmail.com"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519
fi
    
xclip -selection clipboard <~/.ssh/id_ed25519.pub
read -n 1 -s -r -p "ssh key was copied. Add it to github. Press any key to continue"
    
rm -f "$HOME/.gitignore" || :
echo "dots" > "$HOME/.gitignore"

rm -rf "$HOME/dots" || :
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

# Desktop theming the checked-out configs assume: GTK theme/icons
# (~/.config/gtk-3.0, gtk-4.0, .gtkrc-2.0) and the compositor xmonad spawns.
sudo apt install -y yaru-theme-gtk yaru-theme-icon picom

# Nerd Font used by xmonad tabs, xmobar, rofi, dunst, alacritty and GTK;
# not packaged by apt, so fetch the release zip into the user font dir.
FONT_DIR="$HOME/.local/share/fonts/NerdFonts"
if ! fc-list | grep -q "JetBrainsMono Nerd Font"; then
    mkdir -p "$FONT_DIR"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/JetBrainsMono.zip" \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -q -o "$tmp/JetBrainsMono.zip" -d "$FONT_DIR"
    rm -rf "$tmp"
    fc-cache -f
fi

echo "Done"
