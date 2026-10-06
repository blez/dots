#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: setup.sh [-y|--yes | -i|--ignore-updates]

Installs missing tools and offers available upgrades with a [Y/n] prompt.
apt packages are always upgraded (update + full-upgrade), without a prompt.
If both -y and -i are given, the last one wins.

  -y, --yes             Answer yes to every upgrade prompt. Emacs is still only
                        reported (it's installed manually) and Go stays pinned.
                        sudo may still ask for your password: run it from a
                        terminal, or have sudo credentials cached (sudo -v).
  -i, --ignore-updates  Only report available tool upgrades; don't ask, don't
                        upgrade them. Missing tools are still installed, and apt
                        packages are still upgraded.
  -h, --help            Show this help.
USAGE
}

# What to do with available tool upgrades: ask (default), yes (--yes) or
# report (--ignore-updates). The last of these flags wins.
update_mode=ask
while [ $# -gt 0 ]; do
    case "$1" in
        -i | --ignore-updates) update_mode=report ;;
        -y | --yes) update_mode=yes ;;
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
# reads from the terminal. With --yes every upgrade is installed without
# asking (terminal or not); with --ignore-updates, or with no terminal to ask
# on, the upgrade is only reported and listed again in a summary at the end.
# apt packages are the exception: they are always upgraded, without a prompt.
# ---------------------------------------------------------------------------

# step MESSAGE -- progress line before a slow step (mostly network lookups),
# so a long wait shows what it is waiting for instead of looking like a hang.
step() {
    if [ -t 1 ]; then
        printf '\033[1;34m==>\033[0m %s\n' "$*"
    else
        printf '==> %s\n' "$*"
    fi
}

# Time limit (seconds) for each "latest version" lookup, so an unresponsive
# server makes the lookup fail ("could not look up ...") instead of hanging.
lookup_timeout=30

# try NAME CMD... -- run an install/upgrade step without letting its failure
# end the whole script: the failure is listed under "Failed to install" at the
# end and the next tool is checked. CMD still stops at its own first failing
# command (errexit stays on inside the subshell); running it in an `if` or with
# `||` instead would silently turn that off for everything CMD runs.
try() {
    local name=$1 rc
    shift
    set +e
    (set -e; "$@")
    rc=$?
    set -e
    if [ "$rc" != 0 ]; then
        echo "$name: failed (exit $rc), continuing" >&2
        failed_installs+=("$name (exit $rc)")
    fi
}

# run_in_dir DIR CMD... -- run CMD with DIR as working directory (used with
# try, whose subshell keeps the cd from leaking out).
run_in_dir() {
    cd "$1"
    shift
    "$@"
}

# confirm QUESTION -- yes unless the answer starts with n/N (always yes with
# --yes, without asking). QUESTION reads
# "<what is available>. Do you want to ...?"; when not asking, only the first
# part is reported and remembered for the summary.
skipped_updates=()
confirm() {
    local answer
    if [ "$update_mode" = yes ]; then
        echo "${1% Do you want*} Upgrading (--yes)."
        return 0
    fi
    if [ "$update_mode" = ask ] && (exec </dev/tty) 2>/dev/null &&
        read -r -p "$1 [Y/n] " answer </dev/tty; then
        case "$answer" in
            [nN]*) return 1 ;;
            *) return 0 ;;
        esac
    fi
    skipped_updates+=("${1% Do you want*}")
    if [ "$update_mode" = report ]; then
        echo "${1% Do you want*}"
    else
        echo "$1 [no terminal, skipped]"
    fi
    return 1
}

# ver CMD... -- first version-looking token of CMD's output, "" if CMD is missing.
# Takes the first version on any line, not just the first line: some tools
# (yazi 26.9+) print only their name on the first line.
ver() {
    command -v "$1" >/dev/null || return 0
    "$@" 2>/dev/null </dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?' | head -1 || :
}

# latest_tag REPO_URL -- newest stable tag (rc/beta/dev/vNext excluded), "" on failure.
latest_tag() {
    timeout "$lookup_timeout" git ls-remote --tags --refs "$1" 2>/dev/null | sed 's|.*refs/tags/||' |
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
    step "Checking $name for updates..."
    if ! timeout "$lookup_timeout" git -C "$dir" fetch --quiet 2>/dev/null; then
        echo "$name: could not fetch updates, skipping update check" >&2
        return 0
    fi
    behind="$(git -C "$dir" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
    [ "$behind" -gt 0 ] || return 0
    if confirm "$name: $behind new upstream commits available. Do you want to update?"; then
        if [ $# -gt 0 ]; then
            try "$name" run_in_dir "$dir" "$@"
        else
            try "$name" git -C "$dir" pull --ff-only --quiet
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
    step "Checking $pkg (npm) for updates..."
    [ -n "$npm_json" ] || npm_json="$(npm ls -g --depth=0 --json 2>/dev/null || echo '{}')"
    current="$(jq -r --arg p "$pkg" '.dependencies[$p].version // empty' <<<"$npm_json" || :)"
    latest="$(timeout "$lookup_timeout" npm view "$pkg" version 2>/dev/null || :)"
    if want_install "$pkg" "$current" "$latest"; then
        try "$pkg (npm)" sudo npm install -g "$pkg@latest"
        npm_json=""
    fi
}

pipx_json=""
pipx_tool() {
    local pkg=$1 key current latest
    step "Checking $pkg (pipx) for updates..."
    key="$(echo "$pkg" | tr 'A-Z_' 'a-z-')"
    [ -n "$pipx_json" ] || pipx_json="$(pipx list --json 2>/dev/null || echo '{}')"
    current="$(jq -r --arg p "$key" '.venvs[$p].metadata.main_package.package_version // empty' <<<"$pipx_json" || :)"
    latest="$(curl -fsS --max-time "$lookup_timeout" "https://pypi.org/pypi/$pkg/json" 2>/dev/null | jq -r '.info.version // empty' || :)"
    if want_install "$pkg" "$current" "$latest"; then
        if [ -z "$current" ]; then
            try "$pkg (pipx)" pipx install "$pkg"
        else
            try "$pkg (pipx)" pipx upgrade "$pkg"
        fi
    fi
}

go_tool() {
    local pkg=$1 bin=${1##*/} path mod="" current="" latest=""
    step "Checking $bin (go) for updates..."
    if path="$(command -v "$bin")"; then
        read -r mod current < <(go version -m "$path" 2>/dev/null | awk '$1 == "mod" {print $2, $3; exit}') || :
        [ -z "$mod" ] || latest="$(timeout "$lookup_timeout" go list -m -f '{{.Version}}' "$mod@latest" 2>/dev/null || :)"
    fi
    if want_install "$bin" "$current" "$latest"; then
        if ! go install "$pkg@latest"; then
            echo "$bin: go install failed" >&2
            failed_installs+=("$bin (go install $pkg@latest)")
        fi
    fi
}

# ---------------------------------------------------------------------------

# apt_get ARGS... -- apt-get that never stops for a question. When an upgrade
# ships a new version of a config file you changed, dpkg would ask which one
# to keep, and without a terminal it can't get an answer and leaves the package
# half-configured. Instead: keep your version (the new one is saved next to it
# as .dpkg-dist), or take the new one if you never changed it.
apt_get() {
    sudo env DEBIAN_FRONTEND=noninteractive apt-get -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# -n: don't refresh the package index here; apt_get update below does it once.
sudo add-apt-repository -y -n universe

# 1Password app and CLI (op) come from 1Password's own apt repository, set up
# as in https://support.1password.com/install-linux/ . The deb822 file below is
# the one the 1password package manages afterwards, so it's only written when
# no 1Password source exists yet. The debsig policy lets dpkg verify the
# packages' signatures.
add_1password_repo() {
    local key
    key="$(curl -fsS --max-time "$lookup_timeout" https://downloads.1password.com/linux/keys/1password.asc)" || return 1
    sudo gpg --dearmor --yes --output /usr/share/keyrings/1password-archive-keyring.gpg <<<"$key" || return 1
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22 || return 1
    curl -fsS --max-time "$lookup_timeout" https://downloads.1password.com/linux/debian/debsig/1password.pol |
        sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null || return 1
    sudo gpg --dearmor --yes --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg <<<"$key" || return 1
    # Written last: this file is what marks the repository as set up, so a
    # failure above makes the next run try the whole thing again.
    sudo tee /etc/apt/sources.list.d/1password.sources >/dev/null <<'SOURCES' || return 1
Types: deb
URIs: https://downloads.1password.com/linux/debian/amd64
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/1password-archive-keyring.gpg
SOURCES
}
if [ ! -e /etc/apt/sources.list.d/1password.sources ] && [ ! -e /etc/apt/sources.list.d/1password.list ]; then
    step "Adding the 1Password apt repository..."
    if ! add_1password_repo; then
        failed_installs+=("1Password apt repository (download or setup failed; retried next run)")
    fi
fi
# apt always runs in full, with no prompt (also with --ignore-updates).
step "Updating apt packages..."
apt_get update
apt_get full-upgrade
apt_get autoremove

apt_packages=(
    1password
    1password-cli # op: fetches the dotfiles' git-crypt key
    alsa-utils
    apache2-utils
    autoconf
    automake
    bat
    btop
    bluez
    build-essential
    ca-certificates
    clang
    clangd
    clang-format
    cmake
    curl
    default-jdk
    deluge
    direnv
    suckless-tools # provides dmenu
    dsniff
    dh-autoreconf
    editorconfig
    eza
    fonts-symbola
    ffmpeg
    flameshot
    flatpak # WhatsApp (ZapZap) comes from Flathub
    gawk
    g++
    g++-14
    git
    git-crypt # decrypts the encrypted dotfiles (see ~/.gitattributes)
    gnupg
    graphviz
    glslang-tools
    i3lock
    xss-lock # locks before sleep / on loginctl lock-session (xmonad startup hook)
    imagemagick
    isync
    jq
    libvips-dev
    libxcb-res0-dev
    libopencv-dev
    libnotify-dev
    libxaw7-dev
    libx11-dev
    libayatana-appindicator3-1
    libarchive-dev
    libasound2-dev
    libsixel-dev
    libspa-0.2-bluetooth
    libchafa-dev
    libstdc++-14-dev
    libtbb-dev
    libffi-dev
    libgmp-dev
    libncurses-dev
    libc6-dev
    libjpeg-dev
    libtiff-dev
    libfreetype-dev
    libfontconfig1-dev
    libtree-sitter-dev
    libxcb-xfixes0-dev
    libxkbcommon-dev
    libgccjit-14-dev
    libgnutls28-dev
    gnutls-bin
    libjson-c-dev
    libjson-glib-dev
    libjansson-dev
    libgtk-3-dev
    libgtk-layer-shell-dev
    libpango1.0-dev
    libwxgtk3.2-dev
    libcairo2-dev
    libcairo-gobject2
    libneon27-dev
    libxpm-dev
    libxext-dev
    libxcb1-dev
    libxcb-dpms0-dev
    libxcb-damage0-dev
    libxcb-shape0-dev
    libxcb-render-util0-dev
    libxcb-util-dev
    libepoxy-dev
    libxcb-render0-dev
    libxcb-randr0-dev
    libxcb-composite0-dev
    libxcb-image0-dev
    libxcb-present-dev
    libxcb-xinerama0-dev
    libxcb-xrm-dev
    libxcb-glx0-dev
    libpixman-1-dev
    libdbus-1-dev
    libconfig-dev
    libcurl4-gnutls-dev
    libgl1-mesa-dev
    libpcre2-dev
    libevdev-dev
    uthash-dev
    libev-dev
    libexpat1-dev
    libx11-xcb-dev
    librsvg2-dev
    libspdlog-dev
    libnfs-dev
    libnotify-bin
    libsqlite3-dev
    libsmbclient-dev
    libssh-dev
    libssl-dev
    libtool-bin
    libuchardet-dev
    libxerces-c-dev
    libxi-dev
    libxft-dev # X11-xft, needed to build xmonad
    libxinerama-dev # X11, needed to build xmonad
    libxrandr-dev # X11, needed to build xmonad
    libpng-dev
    libgif-dev
    libgtk2.0-dev
    libxss-dev
    libwebkit2gtk-4.1-dev libayatana-appindicator3-dev
    lldb
    lxappearance
    maildir-utils
    meson
    m4
    net-tools
    ninja-build
    ncdu
    nitrogen
    pavucontrol
    pcmanfm
    pipx
    poppler-utils
    pkg-config
    playerctl
    pulseaudio
    pulseaudio-utils
    pulseaudio-module-bluetooth
    pipenv
    protobuf-compiler
    python3
    python3-pip
    ranger
    rofi
    shellcheck
    texinfo
    texlive-full
    tidy
    tmux
    unzip
    vim
    vlc
    xwallpaper
    xclip
    xfce4-power-manager
    xournalpp
    xmlto
    zoxide
    zsh
    7zip
)
# Install only the missing ones. Passing installed packages makes apt print a
# "Skipping ..." or "already the newest version" line for each of them, and
# full-upgrade above already keeps them current.
step "Checking for missing apt packages..."
declare -A apt_installed=()
while read -r pkg; do apt_installed[$pkg]=1; done < <(
    dpkg-query -W -f='${Package}\t${db:Status-Status}\n' 2>/dev/null | awk -F'\t' '$2 == "installed" {print $1}')
apt_missing=()
for pkg in "${apt_packages[@]}"; do
    [ -n "${apt_installed[$pkg]:-}" ] || apt_missing+=("$pkg")
done
# A package apt has no candidate for (e.g. 1Password's, when adding its repo
# failed) would make the whole install fail; report it instead.
apt_installable=()
for pkg in "${apt_missing[@]}"; do
    if apt-cache policy "$pkg" 2>/dev/null | grep -q 'Candidate: [^(]'; then
        apt_installable+=("$pkg")
    else
        failed_installs+=("apt: $pkg (no installable version found)")
    fi
done
if [ ${#apt_installable[@]} -gt 0 ]; then
    echo "apt: installing ${apt_installable[*]}"
    apt_get install "${apt_installable[@]}"
fi

# Encrypted dotfiles (git-crypt, paths in ~/.gitattributes): unlock them if
# they're still locked, e.g. on a new machine where dotsetup.sh ran before op
# was installed. dots-unlock.sh does nothing when there's nothing to unlock.
if ! "$HOME/scripts/dots-unlock.sh"; then
    failed_installs+=("dotfiles: encrypted files still locked (see the dots-unlock message above)")
fi

if ! command -v ghcup >/dev/null; then
    step "Installing ghcup..."
    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org |
        BOOTSTRAP_HASKELL_NONINTERACTIVE=1 sh
fi

step "Checking cabal for updates..."
cabal_latest="$(timeout "$lookup_timeout" ghcup list -t cabal -r 2>/dev/null | awk '$3 ~ /(^|,)latest(,|$)/ {print $2}' || :)"
if want_install cabal "$(ver cabal --version)" "$cabal_latest"; then
    step "Installing cabal ${cabal_latest:-latest}..."
    try cabal ghcup install cabal --set "${cabal_latest:-latest}"
fi

# xmonad, built with Stack like the guide this setup follows:
# https://github.com/NapoleonWils0n/cerberus/blob/master/xmonad/xmonad-ubuntu-stack-install.org
# ~/.xmonad holds checkouts of xmonad and xmonad-contrib at their release
# tags, plus the stack.yaml from `stack init`; `stack install` puts the xmonad
# binary in ~/.local/bin, and xmonad then recompiles xmonad.hs with Stack.
if ! command -v stack >/dev/null; then
    step "Installing stack..."
    ghcup install stack recommended --set
fi
xmonad_dir="$HOME/.xmonad"
xmonad_bin="$HOME/.local/bin/xmonad"
# Versions of the last successful `stack install`, so a failed or interrupted
# build is retried on the next run even though the checkouts already moved.
xmonad_stamp="$xmonad_dir/.setup-built"

xm_version() { sed -nE 's/^version:[[:space:]]*//p' "$xmonad_dir/$1/$1.cabal" 2>/dev/null || :; }
# xm_checkout REPO TAG -- shallow clone, or move an existing checkout, to TAG.
xm_checkout() {
    local dir="$xmonad_dir/$1" url="https://github.com/xmonad/$1.git"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" fetch --quiet --depth 1 "$url" tag "$2" &&
            git -C "$dir" -c advice.detachedHead=false checkout --quiet "$2"
    else
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$2" "$url" "$dir"
    fi
}

step "Checking xmonad for updates..."
xm_latest="$(latest_tag https://github.com/xmonad/xmonad.git)"
xmc_latest="$(latest_tag https://github.com/xmonad/xmonad-contrib.git)"
xm_current="$(xm_version xmonad)"
xmc_current="$(xm_version xmonad-contrib)"
# xmonad-contrib only works with a matching xmonad range, so the two are
# installed and upgraded together, with one prompt for the pair.
xmonad_move=0
if [ -z "$xm_latest" ] || [ -z "$xmc_latest" ]; then
    echo "xmonad: could not look up the latest versions, skipping" >&2
elif [ -z "$xm_current" ] || [ -z "$xmc_current" ]; then
    echo "xmonad: not installed, installing xmonad $xm_latest + xmonad-contrib $xmc_latest"
    xmonad_move=1
elif is_newer "$xm_latest" "$xm_current" || is_newer "$xmc_latest" "$xmc_current"; then
    if confirm "xmonad: new versions xmonad $xm_latest + xmonad-contrib $xmc_latest available (installed $xm_current + $xmc_current). Do you want to upgrade?"; then
        xmonad_move=1
    fi
fi
xmonad_checkout_failed=0
if [ "$xmonad_move" = 1 ]; then
    step "Downloading xmonad $xm_latest + xmonad-contrib $xmc_latest..."
    xm_prev="$(git -C "$xmonad_dir/xmonad" rev-parse HEAD 2>/dev/null || :)"
    if ! xm_checkout xmonad "$xm_latest"; then
        failed_installs+=("xmonad (git checkout of xmonad $xm_latest)")
        xmonad_checkout_failed=1
    elif ! xm_checkout xmonad-contrib "$xmc_latest"; then
        failed_installs+=("xmonad (git checkout of xmonad-contrib $xmc_latest)")
        xmonad_checkout_failed=1
        # Keep the pair consistent: put xmonad back where it was, so this
        # run and later ones never build a new xmonad with an old contrib.
        if [ -n "$xm_prev" ]; then
            git -C "$xmonad_dir/xmonad" -c advice.detachedHead=false checkout --quiet "$xm_prev" || :
        fi
    fi
fi

if [ "$xmonad_checkout_failed" = 0 ] &&
    [ -d "$xmonad_dir/xmonad/.git" ] && [ -d "$xmonad_dir/xmonad-contrib/.git" ]; then
    xmonad_want="$(xm_version xmonad) $(xm_version xmonad-contrib)"
    # Existing install from before the stamp: count it as built if its
    # version matches the checkout, instead of rebuilding it.
    if [ ! -f "$xmonad_stamp" ] && [ "$(ver "$xmonad_bin" --version)" = "$(xm_version xmonad)" ]; then
        echo "$xmonad_want" >"$xmonad_stamp"
    fi
    if [ "$(cat "$xmonad_stamp" 2>/dev/null)" != "$xmonad_want" ] || [ ! -x "$xmonad_bin" ]; then
        step "Building xmonad with Stack (can take a while)..."
        if [ ! -f "$xmonad_dir/stack.yaml" ] && ! (cd "$xmonad_dir" && stack init); then
            failed_installs+=("xmonad (stack init in ~/.xmonad; retried next run)")
        elif (cd "$xmonad_dir" && stack install); then
            echo "$xmonad_want" >"$xmonad_stamp"
            # Rebuild the config against the new libraries; the running
            # xmonad picks it up on the next restart (Mod+Shift+R).
            if [ -f "$xmonad_dir/xmonad.hs" ] && ! "$xmonad_bin" --recompile; then
                failed_installs+=("xmonad config (xmonad --recompile, see ~/.xmonad/xmonad.errors)")
            fi
        else
            # The snapshot in stack.yaml is never changed by upgrades, so a new
            # release that needs newer dependencies fails here every run.
            failed_installs+=("xmonad (stack install in ~/.xmonad; retried next run. If it keeps failing after an upgrade, the snapshot in ~/.xmonad/stack.yaml may be too old: run 'stack init --force' there)")
        fi
    fi
fi
if [ ! -x "$xmonad_bin" ]; then
    failed_installs+=("xmonad (not installed; see the output above)")
fi

# Login-screen entry for the XMonad session (no package ships one here).
# Exec relies on ~/.local/bin being on the session's PATH (~/.profile adds it).
if [ ! -f /usr/share/xsessions/xmonad.desktop ]; then
    sudo tee /usr/share/xsessions/xmonad.desktop >/dev/null <<'DESKTOP'
[Desktop Entry]
Name=XMonad
Comment=Lightweight tiling window manager
Exec=xmonad
Type=Application
DesktopNames=XMonad
DESKTOP
fi

step "Checking xmobar for updates..."
xmobar_latest="$(curl -fsS --max-time "$lookup_timeout" -H 'Accept: application/json' https://hackage.haskell.org/package/xmobar/preferred 2>/dev/null |
    jq -r '."normal-version"[0] // empty' || :)"
if want_install xmobar "$(ver xmobar --version)" "$xmobar_latest"; then
    step "Building xmobar $xmobar_latest with cabal (can take a while)..."
    build_xmobar() {
        cabal update
        cabal install xmobar -fall_extensions --overwrite-policy=always
    }
    try xmobar build_xmobar
fi

# dunst: built from the latest release into /usr/local. The outdated distro
# package is purged only once that build exists, so a failed build or lookup
# never leaves you without a notification daemon.
step "Checking dunst for updates..."
dunst_latest="$(latest_tag https://github.com/dunst-project/dunst.git)"
build_dunst() {
    make
    sudo make install
}
if want_install dunst "$(ver /usr/local/bin/dunst --version)" "$dunst_latest" need_latest; then
    step "Building dunst $dunst_latest..."
    try dunst build_from_tag https://github.com/dunst-project/dunst.git "$dunst_latest" build_dunst
fi
# Its binary and D-Bus service file would shadow the build.
if [ -x /usr/local/bin/dunst ] && dpkg -s dunst >/dev/null 2>&1; then
    apt_get purge dunst
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
    step "Installing oh-my-zsh..."
    omz_installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    RUNZSH=no CHSH=no sh -c "$omz_installer" "" --unattended
    # The installer replaces .zshrc; restore ours. Only here, so later runs
    # never discard uncommitted .zshrc edits.
    /usr/bin/git --git-dir="$HOME/dots/" --work-tree="$HOME" checkout .zshrc
fi

for plugin in zsh-users/zsh-autosuggestions Aloxaf/fzf-tab zsh-users/zsh-syntax-highlighting; do
    plugin_dir="$HOME/.oh-my-zsh/custom/plugins/${plugin#*/}"
    if [ ! -d "$plugin_dir" ]; then
        step "Installing ${plugin#*/}..."
        git clone "https://github.com/$plugin.git" "$plugin_dir"
    else
        git_repo_update "${plugin#*/}" "$plugin_dir"
    fi
done

# picom: built from the latest release into /usr/local. The outdated distro
# package is purged only once that build exists, so a failed build or lookup
# never leaves you without a compositor.
step "Checking picom for updates..."
picom_latest="$(latest_tag https://github.com/yshui/picom.git)"
build_picom() {
    meson setup --buildtype=release build
    ninja -C build
    sudo ninja -C build install
}
if want_install picom "$(ver /usr/local/bin/picom --version)" "$picom_latest" need_latest; then
    step "Building picom $picom_latest..."
    try picom build_from_tag https://github.com/yshui/picom.git "$picom_latest" build_picom
fi
# It could shadow the build or reappear on upgrades.
if [ -x /usr/local/bin/picom ] && dpkg -s picom >/dev/null 2>&1; then
    apt_get purge picom
fi

build_xkblayout_state() {
    make
    sudo install -m755 xkblayout-state /usr/local/bin/xkblayout-state
}
if ! command -v xkblayout-state >/dev/null; then
    step "Building xkblayout-state..."
    try xkblayout-state build_from_tag https://github.com/nonpop/xkblayout-state.git "" build_xkblayout_state
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
    step "Installing Font Awesome..."
    try "font awesome" in_temp_dir install_font_awesome
fi

if [ ! -f "$HOME/.nerd-fonts" ]; then
    step "Installing Nerd Fonts (large download, can take a long while)..."
    # The marker is written only after a successful install, so a failed one
    # is tried again on the next run.
    install_nerd_fonts() {
        build_from_tag https://github.com/ryanoasis/nerd-fonts "" ./install.sh
        touch "$HOME/.nerd-fonts"
    }
    try "nerd fonts" install_nerd_fonts
fi

if ! command -v cargo >/dev/null; then
    step "Installing Rust (rustup)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi


# fd: the crate is published as fd-find; cargo builds the latest release once.
step "Checking fd for updates..."
fd_latest="$(latest_tag https://github.com/sharkdp/fd.git)"
if want_install fd "$(ver fd --version)" "$fd_latest"; then
    step "Building fd $fd_latest with cargo (can take a while)..."
    try fd cargo install fd-find --locked
fi

step "Checking alacritty for updates..."
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
    step "Building alacritty $alacritty_latest (can take a while)..."
    try alacritty build_from_tag https://github.com/alacritty/alacritty.git "$alacritty_latest" build_alacritty
fi

step "Checking starship for updates..."
starship_latest="$(latest_tag https://github.com/starship/starship.git)"
if want_install starship "$(ver starship --version)" "$starship_latest"; then
    step "Installing starship $starship_latest..."
    install_starship() {
        local installer
        installer="$(curl -fsSL https://starship.rs/install.sh)"
        sh -c "$installer" -- --yes
    }
    try starship install_starship
fi

# https://github.com/nodesource/distributions
# Install only if node is missing or older than the pinned major (22 LTS).
node_major=0
if command -v node >/dev/null; then
    node_major=$(node --version | sed 's/^v\([0-9]*\).*/\1/')
fi
if [ "$node_major" -lt 22 ]; then
    step "Installing Node.js 22..."
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
    step "Checking pnpm for updates..."
    if want_install pnpm "$(ver "$PNPM_HOME/pnpm" --version)" "$(timeout "$lookup_timeout" npm view @pnpm/exe version 2>/dev/null || :)"; then
        try pnpm "$PNPM_HOME/pnpm" self-update
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
step "Checking deno for updates..."
deno_latest="$(latest_tag https://github.com/denoland/deno.git)"
install_deno() {
    curl -fsSLO "https://github.com/denoland/deno/releases/download/$deno_latest/deno-x86_64-unknown-linux-gnu.zip"
    unzip -q deno-x86_64-unknown-linux-gnu.zip
    mkdir -p ~/.local/bin
    install -m755 deno ~/.local/bin/deno
}
if want_install deno "$(ver deno --version)" "$deno_latest" need_latest; then
    if command -v deno >/dev/null; then
        step "Upgrading deno to $deno_latest..."
        try deno deno upgrade "${deno_latest#v}"
    else
        step "Installing deno $deno_latest..."
        try deno in_temp_dir install_deno
    fi
fi

# Go stays on the version pinned in go-update.sh (work projects need it),
# so it is only installed when missing, never offered for upgrade.
if ! command -v go >/dev/null; then
    step "Installing Go..."
    ~/scripts/go-update.sh
fi

# Go tools: the list lives in go-utils.sh. Each is installed if missing and
# offered for upgrade when its module has a newer release.
for pkg in $(sed -nE 's/^go install ([^@ ]+)@latest.*/\1/p' ~/scripts/go-utils.sh); do
    go_tool "$pkg"
done

if [ ! -d "$HOME/.diff-so-fancy" ]; then
    step "Installing diff-so-fancy..."
    git clone https://github.com/so-fancy/diff-so-fancy.git "$HOME/.diff-so-fancy"
else
    git_repo_update diff-so-fancy "$HOME/.diff-so-fancy"
fi

# Ubuntu/Debian ship bat as "batcat".
if ! command -v bat >/dev/null && command -v batcat >/dev/null; then
    mkdir -p ~/.local/bin
    ln -s "$(command -v batcat)" ~/.local/bin/bat
fi

step "Checking delta for updates..."
delta_latest="$(latest_tag https://github.com/dandavison/delta.git)"
install_delta() {
    curl -fsSL "https://github.com/dandavison/delta/releases/download/$delta_latest/delta-$delta_latest-x86_64-unknown-linux-musl.tar.gz" | tar xz
    mkdir -p ~/.local/bin
    install -m755 delta-*/delta ~/.local/bin/delta
}
if want_install delta "$(ver delta --version)" "$delta_latest" need_latest; then
    step "Installing delta $delta_latest..."
    try delta in_temp_dir install_delta
fi

step "Checking atuin for updates..."
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
    step "Installing atuin $atuin_latest..."
    try atuin in_temp_dir install_atuin
fi

if ! command -v fzf >/dev/null; then
    step "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    # No prompts and no rc edits: .zshrc already sources ~/.fzf.zsh.
    ~/.fzf/install --key-bindings --completion --no-update-rc
elif [ -d ~/.fzf/.git ]; then
    step "Checking fzf for updates..."
    fzf_latest="$(latest_tag https://github.com/junegunn/fzf.git)"
    if want_install fzf "$(ver fzf --version)" "$fzf_latest"; then
        step "Upgrading fzf to $fzf_latest..."
        upgrade_fzf() {
            git -C ~/.fzf pull --ff-only --quiet
            ~/.fzf/install --bin
        }
        try fzf upgrade_fzf
    fi
fi

step "Checking ripgrep for updates..."
rg_latest="$(latest_tag https://github.com/BurntSushi/ripgrep.git)"
install_rg() {
    curl -fsSLO "https://github.com/BurntSushi/ripgrep/releases/download/$rg_latest/ripgrep_${rg_latest}-1_amd64.deb"
    sudo dpkg -i "ripgrep_${rg_latest}-1_amd64.deb"
}
if want_install ripgrep "$(ver rg --version)" "$rg_latest" need_latest; then
    step "Installing ripgrep $rg_latest..."
    try ripgrep in_temp_dir install_rg
fi

# Telegram Desktop: official prebuilt binary in /usr/local/bin, owned by you
# (not root) so Telegram's built-in updater can still replace it.
# The latest non-beta release with a Linux binary comes from the GitHub
# releases API: tag and download URL in one step, both empty if either is
# missing.
step "Checking telegram for updates..."
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
    step "Installing telegram $telegram_latest..."
    try telegram in_temp_dir install_telegram
fi

# Viber: the official .deb. It adds no apt repository, so apt never updates
# it. The latest version is read from the first 256 KB of the package (its
# control data comes first), so checking doesn't download the whole ~130 MB.
step "Checking viber for updates..."
viber_url="https://download.cdn.viber.com/cdn/desktop/Linux/viber.deb"
viber_current="$(dpkg-query -W -f='${db:Status-Status} ${Version}' viber 2>/dev/null |
    sed -n 's/^installed //p' || :)"
viber_latest="$(curl -fsS --max-time "$lookup_timeout" -r 0-262143 "$viber_url" 2>/dev/null |
    dpkg-deb -f /dev/stdin Version 2>/dev/null || :)"
install_viber() {
    curl -fsSLo viber.deb "$viber_url"
    apt_get install ./viber.deb
}
if want_install viber "$viber_current" "$viber_latest" need_latest; then
    step "Installing viber $viber_latest..."
    try viber in_temp_dir install_viber
fi

# WhatsApp: there's no official Linux app. ZapZap is a maintained desktop
# client for WhatsApp Web, from Flathub, installed for this user (no sudo).
# Its version label isn't reliable (new builds keep an old number), so flatpak
# itself decides whether an update is available.
zapzap_id="com.rtosta.zapzap"
timeout "$lookup_timeout" flatpak remote-add --user --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo || :
if ! flatpak info --user "$zapzap_id" >/dev/null 2>&1; then
    step "Installing whatsapp (ZapZap)..."
    if ! flatpak install --user -y --noninteractive flathub "$zapzap_id"; then
        failed_installs+=("whatsapp (flatpak install $zapzap_id)")
    fi
else
    step "Checking whatsapp (ZapZap) for updates..."
    if timeout "$lookup_timeout" flatpak remote-ls --user --updates --app --columns=application 2>/dev/null |
        grep -qxF "$zapzap_id"; then
        if confirm "whatsapp (ZapZap): an update is available. Do you want to upgrade?"; then
            step "Upgrading whatsapp (ZapZap)..."
            try "whatsapp (ZapZap)" flatpak update --user -y --noninteractive "$zapzap_id"
        fi
    fi
fi

# Claude Code: the native install (~/.local/bin/claude). Its own auto-update
# is turned off here, so setup.sh offers updates. "latest" is the installer's
# default release channel.
step "Checking claude code for updates..."
claude_latest="$(curl -fsS --max-time "$lookup_timeout" \
    https://downloads.claude.ai/claude-code-releases/latest 2>/dev/null |
    grep -xE '[0-9]+\.[0-9]+\.[0-9]+' || :)"
if want_install "claude code" "$(ver claude --version)" "$claude_latest" need_latest; then
    step "Installing claude code $claude_latest..."
    install_claude_code() {
        local installer
        installer="$(curl -fsSL --max-time 60 https://claude.ai/install.sh)"
        bash -s -- "$claude_latest" <<<"$installer"
    }
    try "claude code" install_claude_code
fi

step "Checking yazi for updates..."
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
    step "Building yazi $yazi_latest (can take a while)..."
    try yazi build_from_tag https://github.com/sxyazi/yazi.git "$yazi_latest" build_yazi
fi

# Emacs is installed manually; only report whether it's missing or outdated.
emacs_current="$(ver emacs --version)"
if [ -z "$emacs_current" ]; then
    echo "emacs: not installed, install it manually" >&2
    skipped_updates+=("emacs: not installed, install it manually")
else
    step "Checking emacs for updates..."
    # Release tarballs on GNU's download server (git.savannah.gnu.org is far
    # too slow to list tags: minutes, often timing out).
    emacs_latest="$(curl -fsSL --max-time "$lookup_timeout" https://ftp.gnu.org/gnu/emacs/ 2>/dev/null |
        grep -oE 'emacs-[0-9]+(\.[0-9]+)*\.tar\.xz' | grep -oE '[0-9]+(\.[0-9]+)*' | sort -V | tail -1 || :)"
    if [ -z "$emacs_latest" ]; then
        echo "emacs: could not look up the latest version, skipping update check" >&2
    elif is_newer "$emacs_latest" "$emacs_current"; then
        echo "emacs: new version $emacs_latest available (installed $emacs_current), install it manually"
        skipped_updates+=("emacs: new version $emacs_latest available (installed $emacs_current), install it manually")
    fi
fi

# Only with rustup (a distro cargo is updated by apt).
if command -v rustup >/dev/null; then
    step "Checking rust for updates..."
    # rustup prints e.g. "stable-... - update available: 1.98.1 -> 1.99.0".
    rust_updates="$(timeout "$lookup_timeout" rustup check 2>/dev/null | grep -i 'update available' || :)"
    if [ -n "$rust_updates" ]; then
        echo "$rust_updates"
        if confirm "rust: updates available (listed above). Do you want to upgrade?"; then
            step "Upgrading rust..."
            try rust rustup update
        fi
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
