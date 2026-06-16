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
    clangd \
    clang-format \
    cmake \
    curl \
    default-jdk \
    deluge \
    direnv \
    dmenu \
    dsniff \
    dh-autoreconf \
    editorconfig \
    eza \
    fonts-symbola \
    ffmpeg \
    flameshot \
    gawk \
    g++ \
    g++-14 \
    git \
    gnupg \
    glslang-tools \
    i3lock \
    imagemagick \
    isync \
    jq \
    libvips-dev \
    libxcb-res0-dev \
    libopencv-dev \
    libnotify-dev \
    libxaw7-dev \
    libx11-dev \
    libayatana-appindicator3-1 \
    libarchive-dev \
    libasound2-dev \
    libsixel-dev \
    libchafa-dev \
    libstdc++-14-dev \
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
    libgccjit-14-dev \
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
    pipx \
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
    texlive-full \
    tmux \
    unzip \
    vim \
    vlc \
    xwallpaper \
    xclip \
    xfce4-power-manager \
    xournalpp \
    xmlto \
    zoxide \
    7zip

if ! command -v ghcup >/dev/null; then
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
        curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
fi

if ! command -v cabal >/dev/null; then
    ghcup install --set cabal latest
fi

if ! command -v xmonad >/dev/null; then
    echo "Install xmonad" >&2
    exit 1
# https://github.com/NapoleonWils0n/cerberus/blob/master/xmonad/xmonad-ubuntu-stack-install.org
fi

if ! command -v xmobar >/dev/null; then
    cabal update
    cabal install xmobar -fall_extensions
fi

if ! command -v dunst >/dev/null; then
    (
        git clone https://github.com/dunst-project/dunst.git
        cd dunst
        make
        sudo make install
    )
fi

if ! command -v zsh >/dev/null; then
    sudo apt -y install zsh
fi

if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "pavalk6@gmail.com"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519

    xclip -selection clipboard <~/.ssh/id_ed25519.pub
    read -n 1 -s -r -p "ssh key was copied. Add it to github. Press any key to continue"
fi

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Restore .zshrc after oh-my-zsh install so its installer doesn't clobber it.
/usr/bin/git --git-dir="$HOME/dots/" --work-tree="$HOME" checkout .zshrc

if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
fi

if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
fi

# remove default picom
sudo rm /usr/bin/picom || :
if ! command -v picom >/dev/null; then
    (
        cd "$HOME"
        rm -rf picom
        git clone git@github.com:yshui/picom.git
        cd picom
        git checkout "$(curl https://api.github.com/repos/yshui/picom/releases/latest | jq -r .tag_name)"
        git submodule update --init --recursive
        meson --buildtype=release . build
        ninja -C build
        sudo ninja -C build install
    )
    rm -rf "$HOME/picom"
fi

if ! command -v xkblayout-state >/dev/null; then
    (
        cd "$HOME"
        rm -rf xkblayout-state
        git clone git@github.com:nonpop/xkblayout-state.git
        cd xkblayout-state
        make
        sudo mv xkblayout-state /usr/local/bin
    )
    rm -rf "$HOME/xkblayout-state"
fi

if [ ! -d "$HOME/.font-awesome" ]; then
    (
        cd "$HOME"
        curl -LO https://use.fontawesome.com/releases/v5.15.4/fontawesome-free-5.15.4-desktop.zip
        unzip fontawesome-free-5.15.4-desktop.zip
        mv fontawesome-free-5.15.4-desktop .font-awesome
        sudo rm -rf /usr/share/fonts/font-awesome
        sudo cp -r .font-awesome /usr/share/fonts/font-awesome
        fc-cache -f -v
        rm fontawesome-free-5.15.4-desktop.zip
    )
fi

if [ ! -f "$HOME/.nerd-fonts" ]; then
    (
        cd "$HOME"
        rm -rf nerd-fonts
        git clone https://github.com/ryanoasis/nerd-fonts
        cd nerd-fonts
        ./install.sh
    )
    rm -rf "$HOME/nerd-fonts"
    touch "$HOME/.nerd-fonts"
fi

if ! command -v cargo >/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    echo "Do 'source $HOME/.cargo/env' and rerun script"
    exit 0
fi

if ! command -v fd >/dev/null; then
    (
        cd "$HOME"
        rm -rf fd
        git clone https://github.com/sharkdp/fd
        cd fd
        cargo build
        cargo test
        cargo install --path .
    )
    rm -rf "$HOME/fd"
fi

if [ ! -f /usr/local/bin/alacritty ]; then
    (
        cd "$HOME"
        rm -rf alacritty
        git clone https://github.com/alacritty/alacritty.git
        cd alacritty

        cargo build --release
        sudo mv target/release/alacritty /usr/local/bin
        sudo cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg
        sudo desktop-file-install extra/linux/Alacritty.desktop
        sudo update-desktop-database
        mkdir -p "${ZDOTDIR:-~}/.zsh_functions"
        cp extra/completions/_alacritty "${ZDOTDIR:-~}/.zsh_functions/_alacritty"
    )
    rm -rf "$HOME/alacritty"
fi

if ! command -v starship >/dev/null; then
    sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- --yes
fi

# https://github.com/nodesource/distributions
# Install only if node is missing or older than the pinned major (22 LTS).
node_major=0
if command -v node >/dev/null; then
    node_major=$(node --version | sed 's/^v\([0-9]*\).*/\1/')
fi
if [ "$node_major" -lt 22 ]; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
        sudo gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" |
        sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt-get update
    sudo apt-get install nodejs -y
fi

if command -v npm >/dev/null; then
    sudo npm install -g npm
fi

if ! command -v bash-language-server >/dev/null; then
    sudo npm i -g bash-language-server
fi

if ! command -v pnpm >/dev/null; then
    sudo npm install -g @pnpm/exe
fi

if ! command -v stylelint >/dev/null; then
    sudo npm install -g stylelint
fi

if ! command -v js-beautify >/dev/null; then
    sudo npm -g install js-beautify
fi

if ! command -v grammarly-languageserver >/dev/null; then
    pnpm i -g @emacs-grammarly/grammarly-languageserver
fi

if ! command -v rust-analyzer >/dev/null; then
    rustup component add rust-analyzer
fi

if ! command -v deno >/dev/null; then
    cargo install deno --locked
fi

if ! command -v go >/dev/null; then
    ~/scripts/go-update.sh
    ~/scripts/go-utils.sh
fi

if ! command -v yamlfmt >/dev/null; then
    go install github.com/google/yamlfmt/cmd/yamlfmt@latest
fi

if ! command -v dockfmt >/dev/null; then
    go install github.com/jessfraz/dockfmt@latest
fi

if [ ! -d "$HOME/.diff-so-fancy" ]; then
    cd
    git clone git@github.com:so-fancy/diff-so-fancy.git "$HOME/.diff-so-fancy"
fi

if ! command -v fzf >/dev/null; then
    cd
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install
fi

if ! command -v rg >/dev/null; then
    cd
    curl -LO https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep_15.1.0-1_amd64.deb
    sudo dpkg -i ripgrep_15.1.0-1_amd64.deb
    rm ripgrep_15.1.0-1_amd64.deb
fi

if ! command -v yazi >/dev/null; then
    (
        cd "$HOME"
        rm -rf yazi
        git clone https://github.com/sxyazi/yazi.git
        cd yazi
        cargo build --release --locked
        mkdir -p ~/.local/bin
        mv target/release/yazi target/release/ya ~/.local/bin

        ya pkg add yazi-rs/plugins:full-border
        ya pkg add yazi-rs/plugins:smart-enter
        ya pkg add yazi-rs/plugins:smart-paste
        ya pkg add yazi-rs/plugins:chmod
        ya pkg add yazi-rs/plugins:toggle-pane
    )
    rm -rf "$HOME/yazi"
fi

if ! command -v emacs >/dev/null; then
    echo "Install emacs" >&2
    exit 1
fi

if ! command -v doom >/dev/null && [ ! -x ~/.emacs.d/bin/doom ]; then
    cd
    rm -rf ~/.emacs.d
    git clone --depth 1 https://github.com/doomemacs/doomemacs ~/.emacs.d
    ~/.emacs.d/bin/doom install
fi

rustup update

if ! command -v copilot-language-server >/dev/null; then
    sudo npm install -g @github/copilot-language-server
fi

# python3 -m pip install --upgrade pip
pipx install pyflakes
pipx install isort
pipx install pytest
pipx install black
pipx install python-lsp-server
pipx install yt-dlp
pipx install qmk
pipx install tldr
pipx upgrade-all
pipx install cmake-language-server
pipx install Pygments
pipx install curl_cffi

echo "Done."
