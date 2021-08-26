#!/bin/bash
set -euo pipefail

sudo apt update
sudo apt -y install vim \
    curl \
    git \
    xclip \
    direnv \
    cmake \
    pkg-config \
    libfreetype6-dev libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev \
    python3 \
    compton \
    dunst \
    rofi \
    xmonad libghc-xmonad-contrib-dev xmobar \
    i3lock \
    pulseaudio \
    flameshot \
    nitrogen \
    bluez \
    alsa-utils \
    playerctl \
    libnotify-bin \
    texinfo \
    build-essential \
    libx11-dev libxpm-dev libjpeg-dev libpng-dev libgif-dev libtiff-dev libgtk2.0-dev \
    libncurses-dev libxpm-dev automake autoconf \
    libgccjit-10-dev libgnutls28-dev gnutls-bin libjson-c-dev libjson-glib-dev libjansson-dev \
    libtool-bin \
    fd-find \
    editorconfig \
    bat \
    fzf \
    ranger \
    ncdu \
    pavucontrol \
    pcmanfm \
    ncdu \
    xfce4-power-manager

# zsh
if ! zsh --version; then
    sudo apt -y install zsh
fi

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

if [ ! -d $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
fi

if [ ! -d $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
fi

if ! xkblayout-state print format; then
    cd
    git clone git@github.com:nonpop/xkblayout-state.git
    cd xkblayout-state
    make
    sudo mv xkblayout-state /usr/local/bin
    cd
    rm -rf xkblayout-state
fi

if [ ! -f "$HOME/.nerd-fonts" ]; then
    cd
    git clone https://github.com/ryanoasis/nerd-fonts
    cd nerd-fonts
    sudo ./install.sh
    rm -rf "$HOME/nerd-fonts"
    touch "$HOME/.nerd-fonts"
    cd
fi

if ! cargo --version; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
fi

source $HOME/.cargo/env

if [ ! -f /usr/local/bin/alacritty ]; then
    cd "$HOME"
    rm -rf ./alacritty || :
    git clone https://github.com/alacritty/alacritty.git
    cd alacritty

    cargo build --release
    sudo mv target/release/alacritty /usr/local/bin
    sudo cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg
    sudo desktop-file-install extra/linux/Alacritty.desktop
    sudo update-desktop-database
    mkdir -p ${ZDOTDIR:-~}/.zsh_functions
    cp extra/completions/_alacritty ${ZDOTDIR:-~}/.zsh_functions/_alacritty

    cd "$HOME"
    rm -rf ./alacritty
fi

# startship
if ! starship --version; then
    sh -c "$(curl -fsSL https://starship.rs/install.sh)"
fi

# ssh
if [ ! -f ~/.ssh/id_ed25519 ]; then
        ssh-keygen -t ed25519 -C "pavalk6@gmail.com"
        eval "$(ssh-agent -s)"
        ssh-add ~/.ssh/id_ed25519
fi
xclip -selection clipboard < ~/.ssh/id_ed25519.pub
read -n 1 -s -r -p "ssh key was copied. Add it to github. Press any key to continue"

if ! emacs --version; then
    cd "$HOME"
    rm -rf ./emacs || :

    git clone git://git.savannah.gnu.org/emacs.git
    cd emacs
    make clean
    ./autogen.sh
    ./configure --with-modules --with-native-compilation --with-json --without-pop --with-mailutils
    make bootstrap
    make -j$(nproc)
    sudo make install

    cd "$HOME"
    rm -rf ./emacs
fi

if [ ! -d $HOME/.diff-so-fancy ]; then
    cd
    git clone git@github.com:so-fancy/diff-so-fancy.git $HOME/.diff-so-fancy
fi

# dots
if [ ! -d "$HOME/dots" ]; then
    cd
    git clone --bare git@github.com:blez/dots.git "$HOME/dots"

    function dots {
        /usr/bin/git --git-dir=$HOME/dots/ --work-tree=$HOME $@
    }

    mkdir -p "$HOME/.config-backup"
    echo "Backing up pre-existing dot files."
    mv "$HOME/.zshrc" "$HOME/.config-backup/"

    dots checkout
    dots config status.showUntrackedFiles no
fi

if ! rg --version; then
    cd
    curl -LO https://github.com/BurntSushi/ripgrep/releases/download/12.1.1/ripgrep_12.1.1_amd64.deb
    sudo dpkg -i ripgrep_12.1.1_amd64.deb
    rm ripgrep_12.1.1_amd64.deb
fi

if ! doom version; then
    cd
    git clone --depth 1 https://github.com/hlissner/doom-emacs ~/.emacs.d
    ~/.emacs.d/bin/doom install
fi

echo "Done."
