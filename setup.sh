#!/bin/bash
set -euo pipefail

sudo apt update
sudo apt full-upgrade
sudo apt autoremove
sudo apt -y install \
    alsa-utils \
    autoconf \
    automake \
    bat \
    bluez \
    bluez-tools \
    build-essential \
    clang \
    cmake \
    compton \
    curl \
    direnv \
    deluge \
    dmenu \
    dunst \
    editorconfig \
    fd-find \
    flameshot \
    fzf \
    gawk \
    g++ \
    git \
    i3lock \
    isync \
    libarchive-dev \
    libffi-dev libffi7 libgmp-dev libgmp10 libncurses5 libtinfo5 \
    libc6-dev libjpeg62-turbo libncurses5-dev libtiff5-dev xaw3dg-dev zlib1g-dev \
    libfreetype6-dev libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev \
    libgccjit-10-dev libgnutls28-dev gnutls-bin libjson-c-dev libjson-glib-dev libjansson-dev \
    librust-gdk-sys-dev libgtk-3-dev libgtk-layer-shell-dev libpango1.0-dev \
    libwxgtk3.0-gtk3-dev \
    librust-gdk-pixbuf-sys-dev libcairo2-dev libcairo-gobject2 librust-gio-sys-dev \
    librust-glib-sys-dev librust-gobject-sys-dev \
    libneon27-dev \
    libncurses-dev libxpm-dev \
    libxext-dev \
    libxcb1-dev \
    libxcb-damage0-dev \
    libxcb-shape0-dev \
    libxcb-render-util0-dev \
    libxcb-render0-dev \
    libxcb-randr0-dev \
    libxcb-composite0-dev \
    libxcb-image0-dev \
    libxcb-present-dev \
    libxcb-xinerama0-dev \
    libxcb-glx0-dev \
    libpixman-1-dev\
    libdbus-1-dev \
    libconfig-dev \
    libgl1-mesa-dev \
    libpcre2-dev \
    libpcre3-dev \
    libevdev-dev \
    uthash-dev \
    libev-dev \
    libx11-xcb-dev \
    libspdlog-dev \
    libnfs-dev \
    libnotify-bin \
    libsmbclient-dev \
    libssh-dev \
    libssl-dev \
    libtool-bin \
    libuchardet-dev \
    libxerces-c-dev \
    libxi-dev \
    libx11-dev libxpm-dev libjpeg-dev libpng-dev libgif-dev libtiff-dev libgtk2.0-dev \
    lxappearance \
    maildir-utils \
    meson \
    mu4e \
    m4 \
    ninja-build \
    ncdu \
    nitrogen \
    pavucontrol \
    pcmanfm \
    pkg-config \
    playerctl \
    pulseaudio pulseaudio-utils pulseaudio-module-bluetooth \
    pipenv \
    python3 \
    python3-pip \
    ranger \
    rofi \
    shellcheck \
    texinfo \
    vim \
    vlc \
    xwallpaper \
    xclip \
    xfce4-power-manager \
    xmobar \
    xmonad libghc-xmonad-contrib-dev

# zsh
if ! zsh --version; then
    sudo apt -y install zsh
fi

# ssh
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "pavalk6@gmail.com"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519
    
    xclip -selection clipboard <~/.ssh/id_ed25519.pub
    read -n 1 -s -r -p "ssh key was copied. Add it to github. Press any key to continue"
fi

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
fi

if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
fi

if ! picom --version; then
    cd "$HOME"
    git clone git@github.com:yshui/picom.git
    cd picom
    git checkout "$(curl https://api.github.com/repos/yshui/picom/releases/latest | jq -r .tag_name)"
    git submodule update --init --recursive
    meson --buildtype=release . build
    ninja -C build
    sudo ninja -C build install
    cd "$HOME"
    rm -rf ./picom
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

if [ ! -d "$HOME/.font-awesome" ]; then
    cd "$HOME"
    curl -LO https://use.fontawesome.com/releases/v5.15.4/fontawesome-free-5.15.4-desktop.zip
    unzip fontawesome-free-5.15.4-desktop.zip
    mv fontawesome-free-5.15.4-desktop .font-awesome
    sudo rm -rf /usr/share/fonts/font-awesome
    sudo cp -r .font-awesome /usr/share/fonts/font-awesome
    fc-cache -f -v
    rm fontawesome-free-5.15.4-desktop.zip
fi

if [ ! -f "$HOME/.nerd-fonts" ]; then
    cd
    git clone https://github.com/ryanoasis/nerd-fonts
    cd nerd-fonts
    ./install.sh
    rm -rf "$HOME/nerd-fonts"
    touch "$HOME/.nerd-fonts"
    cd
fi

if ! cargo --version; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    echo "Do 'source $HOME/.cargo/env' and rerun script"
    exit 0
fi

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
    mkdir -p "${ZDOTDIR:-~}/.zsh_functions"
    cp extra/completions/_alacritty "${ZDOTDIR:-~}/.zsh_functions/_alacritty"

    cd "$HOME"
    rm -rf ./alacritty
fi

# startship
if ! starship --version; then
    sh -c "$(curl -fsSL https://starship.rs/install.sh)"
fi

if ! node --version; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    sudo apt-get install -y nodejs
fi

if ! bash-language-server --version; then
    sudo npm i -g bash-language-server
fi

if ! emacs --version; then
    cd "$HOME"
    rm -rf ./emacs || :

    git clone git://git.savannah.gnu.org/emacs.git
    cd emacs
    make clean
    ./autogen.sh
    ./configure --with-modules --with-native-compilation --with-json --without-pop --with-mailutils
    make bootstrap
    make -j "$(nproc)"
    sudo make install

    cd "$HOME"
    curl https://raw.githubusercontent.com/jeetelongname/doom-banners/master/splashes/emacs/emacs-e-logo.png \
        -o ~/.emacs-e-logo.png -s
    rm -rf ./emacs
fi

if [ ! -d "$HOME/.diff-so-fancy" ]; then
    cd
    git clone git@github.com:so-fancy/diff-so-fancy.git "$HOME/.diff-so-fancy"
fi

# dots
if [ ! -d "$HOME/dots" ]; then
    cd
    git clone --bare git@github.com:blez/dots.git "$HOME/dots"

    function dots {
        /usr/bin/git --git-dir="$HOME/dots/" --work-tree="$HOME" "$@"
    }

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
    rm -rf ~/.emacs.d
    git clone --depth 1 https://github.com/hlissner/doom-emacs ~/.emacs.d
    ~/.emacs.d/bin/doom install
fi

pip install --upgrade pyflakes
pip install isort
pip install nose
pip install -U pytest

echo "Done."
