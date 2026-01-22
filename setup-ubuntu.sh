#!/bin/bash
set -euo pipefail

sudo add-apt-repository -y universe
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y

sudo apt install -y \
    alsa-utils \
    apache2-utils \
    autoconf \
    automake \
    bat \
    btop \
    bluez \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    curl \
    default-jre \
    default-jdk \
    deluge \
    direnv \
    dmenu \
    dsniff \
    dunst \
    dh-autoreconf \
    editorconfig \
    eza \
    ffmpeg \
    flameshot \
    gawk \
    g++ \
    git \
    gnupg \
    glslang-tools \
    i3lock \
    imagemagick \
    isync \
    jq \
    libnotify-dev \
    libxaw7-dev \
    libx11-dev \
    libarchive-dev \
    libasound2-dev \
    libvips-dev \
    libsixel-dev \
    libchafa-dev \
    libtbb-dev \
    libffi-dev \
    libgmp-dev \
    libncurses-dev \
    libc6-dev \
    libjpeg-dev \
    libtiff-dev \
    libfreetype6-dev \
    libfontconfig1-dev \
    libtree-sitter-dev \
    libxcb-xfixes0-dev \
    libxkbcommon-dev \
    libgccjit-13-dev \
    libgnutls28-dev \
    gnutls-bin \
    libjson-c-dev \
    libjson-glib-dev \
    libjansson-dev \
    libgtk-3-dev \
    libgtk-layer-shell-dev \
    libpango1.0-dev \
    libwxgtk3.2-dev \
    libcairo2-dev \
    libcairo-gobject2 \
    libneon27-dev \
    libxpm-dev \
    libxext-dev \
    libxcb1-dev \
    libxcb-dpms0-dev \
    libxcb-damage0-dev \
    libxcb-shape0-dev \
    libxcb-render-util0-dev \
    libxcb-render0-dev \
    libxcb-randr0-dev \
    libxcb-composite0-dev \
    libxcb-image0-dev \
    libxcb-present-dev \
    libxcb-xinerama0-dev \
    libxcb-xrm-dev \
    libxcb-glx0-dev \
    libpixman-1-dev \
    libdbus-1-dev \
    libconfig-dev \
    libcurl4-gnutls-dev \
    libgl1-mesa-dev \
    libpcre2-dev \
    libevdev-dev \
    uthash-dev \
    libev-dev \
    libexpat1-dev \
    libx11-xcb-dev \
    librsvg2-dev \
    libspdlog-dev \
    libnfs-dev \
    libnotify-bin \
    libsqlite3-dev \
    libsmbclient-dev \
    libssh-dev \
    libssl-dev \
    libtool-bin \
    libuchardet-dev \
    libxerces-c-dev \
    libxi-dev \
    libx11-dev \
    libpng-dev \
    libgif-dev \
    libgtk2.0-dev \
    libxss-dev \
    lldb \
    lxappearance \
    maildir-utils \
    meson \
    m4 \
    net-tools \
    ninja-build \
    ncdu \
    nitrogen \
    pavucontrol \
    pcmanfm \
    poppler-utils \
    pkg-config \
    playerctl \
    pulseaudio \
    pulseaudio-utils \
    pulseaudio-module-bluetooth \
    pipenv \
    protobuf-compiler \
    python3 \
    python3-pip \
    ranger \
    rofi \
    shellcheck \
    texinfo \
    tmux \
    vim \
    vlc \
    xwallpaper \
    xclip \
    xfce4-power-manager \
    xmlto \
    zoxide \
    picom

if ! ghcup --version; then
    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
fi

if ! cabal --version; then
    ghcup install --set cabal latest
fi

if ! xmonad --version; then
    echo "Install xmonad"
    exit 0
# https://github.com/NapoleonWils0n/cerberus/blob/master/xmonad/xmonad-ubuntu-stack-install.org
fi

if ! xmobar --version; then
    cabal update
    cabal install xmobar -fall_extensions
fi

if ! zsh --version; then
    sudo apt -y install zsh
    /usr/bin/git --git-dir="$HOME/dots/" --work-tree="$HOME" checkout .zshrc
fi

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

# remove default picom
sudo rm /usr/bin/picom || :
if ! picom --version; then
    cd "$HOME"
    rm -rf picom || :
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

if ! fd --version; then
    cd
    rm -rf fd

    git clone https://github.com/sharkdp/fd
    cd fd
    cargo build
    cargo test
    cargo install --path .

    cd
    rm -rf fd
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

if ! starship --version; then
    sh -c "$(curl -fsSL https://starship.rs/install.sh)"
fi

# https://github.com/nodesource/distributions
if ! node --version || [[ $(node --version) != v20* ]]; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
        sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" |
        sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt-get update
    sudo apt-get install nodejs -y
fi

sudo npm install -g npm

if ! bash-language-server --version; then
    sudo npm i -g bash-language-server
fi

if ! pnpm --version; then
    sudo npm install -g @pnpm/exe
fi

if ! stylelint --version; then
    sudo npm install -g stylelint
fi

if ! js-beautify --version; then
    sudo npm -g install js-beautify
fi

if ! grammarly-languageserver --node-ipc; then
    pnpm i -g @emacs-grammarly/grammarly-languageserver
fi

if ! rust-analyzer --version; then
    rustup component add rust-analyzer
fi

if ! deno --version; then
    cargo install deno --locked
fi

if ! go version; then
    ~/scripts/go-update.sh
    ~/scripts/go-utils.sh
fi

if ! yamlfmt --version; then
    go install github.com/google/yamlfmt/cmd/yamlfmt@latest
fi

if ! dockfmt version; then
    go install github.com/jessfraz/dockfmt@latest
fi

if [ ! -d "$HOME/.diff-so-fancy" ]; then
    cd
    git clone git@github.com:so-fancy/diff-so-fancy.git "$HOME/.diff-so-fancy"
fi

if ! fzf --version; then
    cd
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install
    rm -rf ./fzf
fi

if ! rg --version; then
    cd
    curl -LO https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep_15.1.0-1_amd64.deb
    sudo dpkg -i ripgrep_15.1.0-1_amd64.deb
    rm ripgrep_15.1.0-1_amd64.deb
fi

if ! yazi --version; then
    cd
    git clone https://github.com/sxyazi/yazi.git
    cd yazi
    cargo build --release --locked
    mv target/release/yazi target/release/ya ~/.local/bin

    ya pkg add yazi-rs/plugins:full-border
    ya pkg add yazi-rs/plugins:smart-enter
    ya pkg add yazi-rs/plugins:smart-paste
    ya pkg add yazi-rs/plugins:chmod
    ya pkg add yazi-rs/plugins:toggle-pane

    rm -rf ./yazi
fi

if ! doom version; then
    cd
    rm -rf ~/.emacs.d
    git clone --depth 1 https://github.com/doomemacs/doomemacs ~/.emacs.d
    ~/.emacs.d/bin/doom install
fi

rustup update

# python3 -m pip install --upgrade pip
pipx install pyflakes
pipx install isort
pipx install nose
pipx install pytest
pipx install black
pipx install python-lsp-server
pipx install yt-dlp
pipx install qmk
pipx install tldr
pipx upgrade-all

echo "Done."
