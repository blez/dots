#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: setup.sh [-i|--ignore-updates]

Installs missing tools and offers available upgrades with a [Y/n] prompt.

  -i, --ignore-updates  Only report available upgrades; don't ask, don't upgrade.
                        Missing tools are still installed.
  -h, --help            Show this help.
USAGE
}

ignore_updates=0
while [ $# -gt 0 ]; do
    case "$1" in
        -i | --ignore-updates) ignore_updates=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

# Directories this script installs tools into. Login shells add them via
# .zshrc/.profile, but a fresh machine or a plain bash run doesn't have them,
# which makes installed tools look missing and fresh installs unusable.
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export GOPATH="${GOPATH:-$HOME/go}"
# Same priority as the login shell (.zshrc): listed order, first wins.
# Directories already on PATH are left where they are.
path_front=""
for dir in "$PNPM_HOME/bin" "$PNPM_HOME" "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    case ":$PATH:" in *":$dir:"*) ;; *) path_front="$path_front$dir:" ;; esac
done
PATH="$path_front$PATH"
for dir in "$HOME/.cabal/bin" "$HOME/.ghcup/bin" /usr/local/go/bin "$GOPATH/bin" "$HOME/.fzf/bin"; do
    case ":$PATH:" in *":$dir:"*) ;; *) PATH="$PATH:$dir" ;; esac
done
export PATH

# ---------------------------------------------------------------------------
# Update helpers. Missing tools are installed without asking; for installed
# ones a newer upstream version is offered with a [Y/n] prompt. The prompt
# reads from the terminal; with no terminal, or with --ignore-updates, the
# upgrade is only reported and listed again in a summary at the end.
# ---------------------------------------------------------------------------

# confirm QUESTION -- yes unless the answer starts with n/N. QUESTION reads
# "<what is available>. Do you want to ...?"; when not asking, only the first
# part is reported and remembered for the summary.
skipped_updates=()
confirm() {
    local answer
    if [ "$ignore_updates" = 0 ] && (exec </dev/tty) 2>/dev/null &&
        read -r -p "$1 [Y/n] " answer </dev/tty; then
        case "$answer" in
            [nN]*) return 1 ;;
            *) return 0 ;;
        esac
    fi
    skipped_updates+=("${1% Do you want*}")
    if [ "$ignore_updates" = 1 ]; then
        echo "${1% Do you want*}"
    else
        echo "$1 [no terminal, skipped]"
    fi
    return 1
}

# ver CMD... -- first version-looking token of CMD's output, "" if CMD is missing.
ver() {
    command -v "$1" >/dev/null || return 0
    "$@" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?' | head -1 || :
}

# latest_tag REPO_URL -- newest stable tag (rc/beta/dev/vNext excluded), "" on failure.
latest_tag() {
    git ls-remote --tags --refs "$1" 2>/dev/null | sed 's|.*refs/tags/||' |
        grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -1 || :
}

# is_newer A B -- true if version A is newer than B (leading "v" ignored).
# A pre-release/dev build of A (0.17.0-dev, 0.17.0-rc1) counts as older than A;
# a build N commits after release A (git describe: 1.13.2-15) counts as newer.
is_newer() {
    local a=${1#v} b=${2#v}
    [ "$a" != "$b" ] || return 1
    if [ "${b%%-*}" = "$a" ]; then
        case "${b#*-}" in
            [0-9]*) return 1 ;;
            *) return 0 ;;
        esac
    fi
    [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" = "$a" ]
}

# want_install NAME CURRENT LATEST [need_latest]
# True when NAME is missing, or LATEST is newer and the user agrees.
# Pass need_latest when installing is impossible without knowing LATEST.
want_install() {
    local name=$1 current=$2 latest=$3 need_latest=${4:-}
    if [ -z "$current" ]; then
        if [ -z "$latest" ] && [ -n "$need_latest" ]; then
            echo "$name: not installed and the latest version could not be looked up, skipping" >&2
            return 1
        fi
        echo "$name: not installed, installing${latest:+ $latest}"
        return 0
    fi
    if [ -z "$latest" ]; then
        echo "$name: could not look up the latest version, skipping update check" >&2
        return 1
    fi
    is_newer "$latest" "$current" || return 1
    confirm "$name: new version $latest available (installed $current). Do you want to upgrade?"
}

# git_repo_update NAME DIR [COMMAND...] -- for tools that live in a git checkout:
# offer new upstream commits. COMMAND (run in DIR) replaces the default pull.
git_repo_update() {
    local name=$1 dir=$2 behind
    shift 2
    if ! git -C "$dir" fetch --quiet 2>/dev/null; then
        echo "$name: could not fetch updates, skipping update check" >&2
        return 0
    fi
    behind="$(git -C "$dir" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
    [ "$behind" -gt 0 ] || return 0
    if confirm "$name: $behind new upstream commits available. Do you want to update?"; then
        if [ $# -gt 0 ]; then
            (cd "$dir" && "$@")
        else
            git -C "$dir" pull --ff-only --quiet
        fi
    fi
}

# Non-fatal install failures, reported at the end (and setup.sh exits 1).
failed_installs=()

# in_temp_dir CMD... -- run CMD inside a fresh temp dir, then delete the dir.
# Keeps builds and downloads out of $HOME and cleans up after them.
in_temp_dir() {
    local dir
    dir="$(mktemp -d)"
    (
        trap 'rm -rf "$dir"' EXIT
        cd "$dir"
        "$@"
    )
}

# build_from_tag REPO TAG CMD... -- shallow-clone REPO at TAG (default branch
# when TAG is empty) into a temp dir and run CMD inside the checkout.
build_from_tag() {
    local repo=$1 tag=$2
    shift 2
    in_temp_dir _clone_and_run "$repo" "$tag" "$@"
}
_clone_and_run() {
    local repo=$1 tag=$2
    shift 2
    git -c advice.detachedHead=false clone --quiet --depth 1 --recurse-submodules --shallow-submodules \
        ${tag:+--branch "$tag"} "$repo" src
    cd src
    "$@"
}

# npm_tool PKG / pipx_tool PKG / go_tool PKG -- per package manager.
npm_json=""
npm_tool() {
    local pkg=$1 current latest
    [ -n "$npm_json" ] || npm_json="$(npm ls -g --depth=0 --json 2>/dev/null || echo '{}')"
    current="$(jq -r --arg p "$pkg" '.dependencies[$p].version // empty' <<<"$npm_json" || :)"
    latest="$(npm view "$pkg" version 2>/dev/null || :)"
    if want_install "$pkg" "$current" "$latest"; then
        sudo npm install -g "$pkg@latest"
        npm_json=""
    fi
}

pipx_json=""
pipx_tool() {
    local pkg=$1 key current latest
    key="$(echo "$pkg" | tr 'A-Z_' 'a-z-')"
    [ -n "$pipx_json" ] || pipx_json="$(pipx list --json 2>/dev/null || echo '{}')"
    current="$(jq -r --arg p "$key" '.venvs[$p].metadata.main_package.package_version // empty' <<<"$pipx_json" || :)"
    latest="$(curl -fsS "https://pypi.org/pypi/$pkg/json" 2>/dev/null | jq -r '.info.version // empty' || :)"
    if want_install "$pkg" "$current" "$latest"; then
        if [ -z "$current" ]; then
            pipx install "$pkg"
        else
            pipx upgrade "$pkg"
        fi
    fi
}

go_tool() {
    local pkg=$1 bin=${1##*/} path mod="" current="" latest=""
    if path="$(command -v "$bin")"; then
        read -r mod current < <(go version -m "$path" 2>/dev/null | awk '$1 == "mod" {print $2, $3; exit}') || :
        [ -z "$mod" ] || latest="$(go list -m -f '{{.Version}}' "$mod@latest" 2>/dev/null || :)"
    fi
    if want_install "$bin" "$current" "$latest"; then
        if ! go install "$pkg@latest"; then
            echo "$bin: go install failed" >&2
            failed_installs+=("$bin (go install $pkg@latest)")
        fi
    fi
}

# ---------------------------------------------------------------------------

sudo add-apt-repository -y universe
sudo apt update
# Simulate instead of "apt list --upgradable": that also lists phased and
# held-back updates which full-upgrade won't install, so it would nag forever.
apt_upgradable="$(apt-get -s full-upgrade 2>/dev/null | grep -c '^Inst ' || :)"
if [ "$apt_upgradable" -gt 0 ]; then
    if confirm "apt: $apt_upgradable packages can be upgraded. Do you want to upgrade?"; then
        sudo apt full-upgrade -y
    fi
fi
sudo apt autoremove -y

# --no-upgrade: already-installed packages are only upgraded via the prompt above.
sudo apt install -y --no-upgrade \
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
    graphviz \
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
    libspa-0.2-bluetooth \
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
    libxcb-util-dev \
    libepoxy-dev \
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
    libwebkit2gtk-4.1-dev libayatana-appindicator3-dev \
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
    tidy \
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
    zsh \
    7zip

if ! command -v ghcup >/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org |
        BOOTSTRAP_HASKELL_NONINTERACTIVE=1 sh
fi

cabal_latest="$(ghcup list -t cabal -r 2>/dev/null | awk '$3 ~ /(^|,)latest(,|$)/ {print $2}' || :)"
if want_install cabal "$(ver cabal --version)" "$cabal_latest"; then
    ghcup install cabal --set "${cabal_latest:-latest}"
fi

if ! command -v xmonad >/dev/null; then
    echo "Install xmonad" >&2
    exit 1
# https://github.com/NapoleonWils0n/cerberus/blob/master/xmonad/xmonad-ubuntu-stack-install.org
fi

xmobar_latest="$(curl -fsS -H 'Accept: application/json' https://hackage.haskell.org/package/xmobar/preferred 2>/dev/null |
    jq -r '."normal-version"[0] // empty' || :)"
if want_install xmobar "$(ver xmobar --version)" "$xmobar_latest"; then
    cabal update
    cabal install xmobar -fall_extensions --overwrite-policy=always
fi

# dunst: built from the latest release into /usr/local. The outdated distro
# package is purged only once that build exists, so a failed build or lookup
# never leaves you without a notification daemon.
dunst_latest="$(latest_tag https://github.com/dunst-project/dunst.git)"
build_dunst() {
    make
    sudo make install
}
if want_install dunst "$(ver /usr/local/bin/dunst --version)" "$dunst_latest" need_latest; then
    build_from_tag https://github.com/dunst-project/dunst.git "$dunst_latest" build_dunst
fi
# Its binary and D-Bus service file would shadow the build.
if [ -x /usr/local/bin/dunst ] && dpkg -s dunst >/dev/null 2>&1; then
    sudo apt purge -y dunst
fi

if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "pavalk6@gmail.com"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519

    xclip -selection clipboard <~/.ssh/id_ed25519.pub
    read -n 1 -s -r -p "ssh key was copied. Add it to github. Press any key to continue"
fi

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    # Assigning first makes a failed download stop the script; inside
    # sh -c "$(curl ...)" it would run an empty script and carry on.
    omz_installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    RUNZSH=no CHSH=no sh -c "$omz_installer" "" --unattended
    # The installer replaces .zshrc; restore ours. Only here, so later runs
    # never discard uncommitted .zshrc edits.
    /usr/bin/git --git-dir="$HOME/dots/" --work-tree="$HOME" checkout .zshrc
fi

for plugin in zsh-users/zsh-autosuggestions Aloxaf/fzf-tab zsh-users/zsh-syntax-highlighting; do
    plugin_dir="$HOME/.oh-my-zsh/custom/plugins/${plugin#*/}"
    if [ ! -d "$plugin_dir" ]; then
        git clone "https://github.com/$plugin.git" "$plugin_dir"
    else
        git_repo_update "${plugin#*/}" "$plugin_dir"
    fi
done

# picom: built from the latest release into /usr/local. The outdated distro
# package is purged only once that build exists, so a failed build or lookup
# never leaves you without a compositor.
picom_latest="$(latest_tag https://github.com/yshui/picom.git)"
build_picom() {
    meson setup --buildtype=release build
    ninja -C build
    sudo ninja -C build install
}
if want_install picom "$(ver /usr/local/bin/picom --version)" "$picom_latest" need_latest; then
    build_from_tag https://github.com/yshui/picom.git "$picom_latest" build_picom
fi
# It could shadow the build or reappear on upgrades.
if [ -x /usr/local/bin/picom ] && dpkg -s picom >/dev/null 2>&1; then
    sudo apt purge -y picom
fi

build_xkblayout_state() {
    make
    sudo install -m755 xkblayout-state /usr/local/bin/xkblayout-state
}
if ! command -v xkblayout-state >/dev/null; then
    build_from_tag https://github.com/nonpop/xkblayout-state.git "" build_xkblayout_state
fi

# Font Awesome stays on v5 on purpose. ~/.font-awesome is kept as the install marker.
install_font_awesome() {
    curl -fsSLO https://use.fontawesome.com/releases/v5.15.4/fontawesome-free-5.15.4-desktop.zip
    unzip -q fontawesome-free-5.15.4-desktop.zip
    mv fontawesome-free-5.15.4-desktop "$HOME/.font-awesome"
    sudo rm -rf /usr/share/fonts/font-awesome
    sudo cp -r "$HOME/.font-awesome" /usr/share/fonts/font-awesome
    fc-cache -f
}
if [ ! -d "$HOME/.font-awesome" ]; then
    in_temp_dir install_font_awesome
fi

if [ ! -f "$HOME/.nerd-fonts" ]; then
    build_from_tag https://github.com/ryanoasis/nerd-fonts "" ./install.sh
    touch "$HOME/.nerd-fonts"
fi

if ! command -v cargo >/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi


# fd: the crate is published as fd-find; cargo builds the latest release once.
fd_latest="$(latest_tag https://github.com/sharkdp/fd.git)"
if want_install fd "$(ver fd --version)" "$fd_latest"; then
    cargo install fd-find --locked
fi

alacritty_latest="$(latest_tag https://github.com/alacritty/alacritty.git)"
build_alacritty() {
    cargo build --release
    sudo install -m755 target/release/alacritty /usr/local/bin/alacritty
    sudo cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg
    sudo desktop-file-install extra/linux/Alacritty.desktop
    sudo update-desktop-database
    mkdir -p "${ZDOTDIR:-$HOME}/.zsh_functions"
    cp extra/completions/_alacritty "${ZDOTDIR:-$HOME}/.zsh_functions/_alacritty"
}
if want_install alacritty "$(ver alacritty --version)" "$alacritty_latest"; then
    build_from_tag https://github.com/alacritty/alacritty.git "$alacritty_latest" build_alacritty
fi

starship_latest="$(latest_tag https://github.com/starship/starship.git)"
if want_install starship "$(ver starship --version)" "$starship_latest"; then
    starship_installer="$(curl -fsSL https://starship.rs/install.sh)"
    sh -c "$starship_installer" -- --yes
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
    npm_tool npm
fi

npm_tool bash-language-server
# pnpm self-installs into $PNPM_HOME, which comes first on PATH; upgrading the
# npm-installed copy would leave the one actually in use untouched.
if [ -x "$PNPM_HOME/pnpm" ]; then
    if want_install pnpm "$(ver "$PNPM_HOME/pnpm" --version)" "$(npm view @pnpm/exe version 2>/dev/null || :)"; then
        "$PNPM_HOME/pnpm" self-update
    fi
else
    npm_tool @pnpm/exe
fi
npm_tool stylelint
npm_tool js-beautify

# rustup always puts a rust-analyzer proxy in ~/.cargo/bin, so check the
# component itself, not the command.
# Only with rustup: a distro cargo has no rustup to add components with.
if command -v rustup >/dev/null &&
    ! rustup component list --installed 2>/dev/null | grep -q '^rust-analyzer'; then
    rustup component add rust-analyzer
fi

# deno: prebuilt release binary instead of a cargo build (seconds, not tens of
# minutes). An existing install upgrades itself in place, wherever it lives.
deno_latest="$(latest_tag https://github.com/denoland/deno.git)"
install_deno() {
    curl -fsSLO "https://github.com/denoland/deno/releases/download/$deno_latest/deno-x86_64-unknown-linux-gnu.zip"
    unzip -q deno-x86_64-unknown-linux-gnu.zip
    mkdir -p ~/.local/bin
    install -m755 deno ~/.local/bin/deno
}
if want_install deno "$(ver deno --version)" "$deno_latest" need_latest; then
    if command -v deno >/dev/null; then
        deno upgrade "${deno_latest#v}"
    else
        in_temp_dir install_deno
    fi
fi

# Go stays on the version pinned in go-update.sh (work projects need it),
# so it is only installed when missing, never offered for upgrade.
if ! command -v go >/dev/null; then
    ~/scripts/go-update.sh
fi

# Go tools: the list lives in go-utils.sh. Each is installed if missing and
# offered for upgrade when its module has a newer release.
for pkg in $(sed -nE 's/^go install ([^@ ]+)@latest.*/\1/p' ~/scripts/go-utils.sh); do
    go_tool "$pkg"
done

if [ ! -d "$HOME/.diff-so-fancy" ]; then
    git clone https://github.com/so-fancy/diff-so-fancy.git "$HOME/.diff-so-fancy"
else
    git_repo_update diff-so-fancy "$HOME/.diff-so-fancy"
fi

# Ubuntu/Debian ship bat as "batcat".
if ! command -v bat >/dev/null && command -v batcat >/dev/null; then
    mkdir -p ~/.local/bin
    ln -s "$(command -v batcat)" ~/.local/bin/bat
fi

delta_latest="$(latest_tag https://github.com/dandavison/delta.git)"
install_delta() {
    curl -fsSL "https://github.com/dandavison/delta/releases/download/$delta_latest/delta-$delta_latest-x86_64-unknown-linux-musl.tar.gz" | tar xz
    mkdir -p ~/.local/bin
    install -m755 delta-*/delta ~/.local/bin/delta
}
if want_install delta "$(ver delta --version)" "$delta_latest" need_latest; then
    in_temp_dir install_delta
fi

atuin_current="$(ver atuin --version)"
atuin_latest="$(latest_tag https://github.com/atuinsh/atuin.git)"
install_atuin() {
    curl -fsSL "https://github.com/atuinsh/atuin/releases/download/$atuin_latest/atuin-x86_64-unknown-linux-musl.tar.gz" | tar xz
    mkdir -p ~/.local/bin
    install -m755 atuin-*/atuin ~/.local/bin/atuin
    if [ -z "$atuin_current" ]; then
        ~/.local/bin/atuin import auto || true
    fi
}
if want_install atuin "$atuin_current" "$atuin_latest" need_latest; then
    in_temp_dir install_atuin
fi

if ! command -v fzf >/dev/null; then
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    # No prompts and no rc edits: .zshrc already sources ~/.fzf.zsh.
    ~/.fzf/install --key-bindings --completion --no-update-rc
elif [ -d ~/.fzf/.git ]; then
    fzf_latest="$(latest_tag https://github.com/junegunn/fzf.git)"
    if want_install fzf "$(ver fzf --version)" "$fzf_latest"; then
        git -C ~/.fzf pull --ff-only --quiet
        ~/.fzf/install --bin
    fi
fi

rg_latest="$(latest_tag https://github.com/BurntSushi/ripgrep.git)"
install_rg() {
    curl -fsSLO "https://github.com/BurntSushi/ripgrep/releases/download/$rg_latest/ripgrep_${rg_latest}-1_amd64.deb"
    sudo dpkg -i "ripgrep_${rg_latest}-1_amd64.deb"
}
if want_install ripgrep "$(ver rg --version)" "$rg_latest" need_latest; then
    in_temp_dir install_rg
fi

# Telegram Desktop: official prebuilt binary in /usr/local/bin, owned by you
# (not root) so Telegram's built-in updater can still replace it.
# The latest non-beta release with a Linux binary comes from the GitHub
# releases API: tag and download URL in one step, both empty if either is
# missing.
IFS=$'\t' read -r telegram_latest telegram_url < <(curl -fsS --max-time 10 \
    https://api.github.com/repos/telegramdesktop/tdesktop/releases/latest 2>/dev/null |
    jq -r '.tag_name as $tag
        | first(.assets[] | select(.label == "Linux 64 bit: Binary"))
        | select($tag != null and .browser_download_url != null)
        | [$tag, .browser_download_url] | @tsv' 2>/dev/null) || :
# Installed version: Telegram has no --version flag, but its log records the
# version on every launch ("Launched version: 7002009" = 7.2.9), which also
# picks up its self-updates. Until Telegram restarts after setup.sh installs
# a new one, the log still shows the old version, so setup.sh also records
# what it installed; the newer of the two wins.
telegram_marker="${XDG_STATE_HOME:-$HOME/.local/state}/telegram-version"
telegram_current=""
if [ -x /usr/local/bin/Telegram ]; then
    telegram_current="$(
        {
            sed -nE 's/.*Launched version: ([0-9]+).*/\1/p' \
                ~/.local/share/TelegramDesktop/log.txt 2>/dev/null | tail -1 |
                awk '{printf "%d.%d.%d\n", $1 / 1000000, ($1 / 1000) % 1000, $1 % 1000}'
            grep -xE '[0-9]+(\.[0-9]+)*' "$telegram_marker" 2>/dev/null
        } | sort -V | tail -1 || :
    )"
    # Installed but version unknown (never launched): offer the latest.
    telegram_current="${telegram_current:-0 (unknown)}"
fi
install_telegram() {
    curl -fsSL "$telegram_url" | tar xJ
    sudo install -o "$(id -un)" -g "$(id -gn)" -m755 \
        Telegram/Telegram Telegram/Updater /usr/local/bin/
    mkdir -p "$(dirname "$telegram_marker")"
    echo "${telegram_latest#v}" >"$telegram_marker"
    echo "telegram: installed $telegram_latest (restart Telegram if it's running)"
}
if want_install telegram "$telegram_current" "$telegram_latest" need_latest; then
    in_temp_dir install_telegram
fi

yazi_current="$(ver yazi --version)"
yazi_latest="$(latest_tag https://github.com/sxyazi/yazi.git)"
build_yazi() {
    cargo build --release --locked
    mkdir -p ~/.local/bin
    install -m755 target/release/yazi target/release/ya ~/.local/bin/

    # Plugins only on a fresh install; "ya pkg add" fails if already added.
    if [ -z "$yazi_current" ]; then
        ya pkg add yazi-rs/plugins:full-border
        ya pkg add yazi-rs/plugins:smart-enter
        ya pkg add yazi-rs/plugins:smart-paste
        ya pkg add yazi-rs/plugins:chmod
        ya pkg add yazi-rs/plugins:toggle-pane
    fi
}
if want_install yazi "$yazi_current" "$yazi_latest"; then
    build_from_tag https://github.com/sxyazi/yazi.git "$yazi_latest" build_yazi
fi

# Emacs is installed manually; only report whether it's missing or outdated.
emacs_current="$(ver emacs --version)"
emacs_latest="$(git ls-remote --tags --refs https://git.savannah.gnu.org/git/emacs.git 2>/dev/null |
    sed 's|.*refs/tags/||' | grep -E '^emacs-[0-9]+(\.[0-9]+)*$' | sed 's/^emacs-//' | sort -V | tail -1 || :)"
if [ -z "$emacs_current" ]; then
    echo "emacs: not installed, install it manually" >&2
    skipped_updates+=("emacs: not installed, install it manually")
elif [ -n "$emacs_latest" ] && is_newer "$emacs_latest" "$emacs_current"; then
    echo "emacs: new version $emacs_latest available (installed $emacs_current), install it manually"
    skipped_updates+=("emacs: new version $emacs_latest available (installed $emacs_current), install it manually")
fi

rust_updates="$(rustup check 2>/dev/null | grep 'Update available' || :)"
if [ -n "$rust_updates" ]; then
    echo "$rust_updates"
    if confirm "rust: updates available (listed above). Do you want to upgrade?"; then
        rustup update
    fi
fi

npm_tool @github/copilot-language-server

# python3 -m pip install --upgrade pip
for pkg in pyflakes isort pytest black python-lsp-server yt-dlp qmk tldr \
    cmake-language-server Pygments curl_cffi; do
    pipx_tool "$pkg"
done

if [ ${#skipped_updates[@]} -gt 0 ]; then
    echo
    echo "Updates available but not installed:"
    printf '  %s\n' "${skipped_updates[@]}"
fi

if [ ${#failed_installs[@]} -gt 0 ]; then
    echo
    echo "Failed to install:" >&2
    printf '  %s\n' "${failed_installs[@]}" >&2
    exit 1
fi

echo "Done."
