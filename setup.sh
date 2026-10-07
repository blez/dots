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

# One run at a time: a second setup.sh would race this one on apt's package
# cache (missing packages then look uninstallable) and on the tools being
# installed. The script re-runs itself under flock, which holds the lock for
# the whole run; -o keeps the lock out of child processes (ssh-agent).
setup_lock="${XDG_RUNTIME_DIR:-/tmp}/setup.sh.lock"
if [ -z "${SETUP_SH_LOCKED:-}" ]; then
    rc=0
    SETUP_SH_LOCKED=1 flock -n -o -E 200 "$setup_lock" bash "$0" "$@" || rc=$?
    if [ "$rc" = 200 ]; then
        echo "setup.sh: another run is still going (maybe waiting at a prompt). Finish that one first." >&2
    fi
    exit "$rc"
fi

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
for dir in "$HOME/.cabal/bin" "$HOME/.ghcup/bin" /usr/local/go/bin "$GOPATH/bin" "$HOME/.fzf/bin" "$HOME/.krew/bin"; do
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
# x.y and x.y.0 name the same release (calibre prints 9.15 for its v9.15.0).
strip_zero() {
    local base=${1%%-*} rest=${1#"${1%%-*}"}
    while [[ $base == *.0 ]]; do base=${base%.0}; done
    echo "$base$rest"
}
is_newer() {
    local a b
    a="$(strip_zero "${1#v}")"
    b="$(strip_zero "${2#v}")"
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

# go_tool [GO-INSTALL-FLAGS...] PKG -- flags (e.g. -tags=postgres) go to go install.
go_tool() {
    local pkg=${*: -1} flags=("${@:1:$#-1}") bin path mod="" current="" latest=""
    bin=${pkg##*/}
    step "Checking $bin (go) for updates..."
    if path="$(command -v "$bin")"; then
        read -r mod current < <(go version -m "$path" 2>/dev/null | awk '$1 == "mod" {print $2, $3; exit}') || :
        [ -z "$mod" ] || latest="$(timeout "$lookup_timeout" go list -m -f '{{.Version}}' "$mod@latest" 2>/dev/null || :)"
    fi
    if want_install "$bin" "$current" "$latest"; then
        if ! go install "${flags[@]}" "$pkg@latest"; then
            echo "$bin: go install failed" >&2
            failed_installs+=("$bin (go install ${flags[*]} $pkg@latest)")
        fi
    fi
}

# cargo_tool BIN CRATE -- Rust tools built from crates.io. The latest version
# is crates.io's (a GitHub tag may be published there only later).
cargo_list=""
cargo_tool() {
    local bin=$1 crate=$2 current latest
    step "Checking $bin for updates..."
    # cargo's own list first, since not every tool has a --version (kalker);
    # --version for a copy that came from elsewhere (apt, a binary).
    [ -n "$cargo_list" ] || cargo_list="$(cargo install --list 2>/dev/null || echo none)"
    current="$(sed -n "s/^$crate v\([0-9][^ :]*\).*/\1/p" <<<"$cargo_list" | head -1 || :)"
    [ -n "$current" ] || current="$(ver "$bin" --version)"
    latest="$(curl -fsS --max-time "$lookup_timeout" -A setup.sh "https://crates.io/api/v1/crates/$crate" 2>/dev/null |
        jq -r '.crate.max_stable_version // empty' || :)"
    if want_install "$bin" "$current" "$latest"; then
        step "Building $bin $latest with cargo (can take a while)..."
        try "$bin" cargo install "$crate" --locked
    fi
}

# deb_version PKG -- installed version of an apt package, "" if not installed.
deb_version() {
    dpkg-query -W -f='${db:Status-Status} ${Version}' "$1" 2>/dev/null | sed -n 's/^installed //p' || :
}

# install_deb URL -- download a .deb and install it with apt (which also
# pulls in its dependencies). Run inside in_temp_dir.
install_deb() {
    curl -fsSLo pkg.deb "$1"
    # mktemp's directory is 700; let apt's _apt user read the package, or
    # apt warns that it downloads unsandboxed as root.
    chmod 755 . && chmod 644 pkg.deb
    apt_get install ./pkg.deb
}

# flatpak_app NAME ID -- Flathub app. Missing ones are installed for this
# user (no sudo); an existing system-wide install is updated as such.
# Version labels aren't reliable (ZapZap's new builds keep an old number), so
# flatpak itself decides whether an update is available. The lookup runs
# once (both scopes) and is cached in flatpak_updates.
flatpak_list=""
flatpak_app() {
    local name=$1 id=$2 scope
    [ -n "$flatpak_list" ] || flatpak_list="$(flatpak list --app --columns=application,installation 2>/dev/null || echo none)"
    scope="$(awk -F'\t' -v id="$id" '$1 == id {print $2; exit}' <<<"$flatpak_list" || :)"
    if [ -z "$scope" ]; then
        step "Installing $name..."
        if ! flatpak install --user -y --noninteractive flathub "$id"; then
            failed_installs+=("$name (flatpak install $id)")
        fi
        return 0
    fi
    step "Checking $name for updates..."
    if [ -z "${flatpak_updates+set}" ]; then
        flatpak_updates="$(
            timeout "$lookup_timeout" flatpak remote-ls --user --updates --app --columns=application 2>/dev/null || echo "lookup failed: user"
            timeout "$lookup_timeout" flatpak remote-ls --system --updates --app --columns=application 2>/dev/null || echo "lookup failed: system"
        )"
    fi
    if grep -qxF "lookup failed: $scope" <<<"$flatpak_updates"; then
        echo "$name: could not look up updates, skipping update check" >&2
    elif grep -qxF "$id" <<<"$flatpak_updates"; then
        if confirm "$name: an update is available. Do you want to upgrade?"; then
            step "Upgrading $name..."
            if [ "$scope" = system ]; then
                try "$name" sudo flatpak update --system -y --noninteractive "$id"
            else
                try "$name" flatpak update --user -y --noninteractive "$id"
            fi
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
sudo add-apt-repository -y -n multiverse # unrar

# add_apt_repo NAME KEY_URL SOURCE_LINE -- a third-party apt repository: the
# signing key goes to /usr/share/keyrings/NAME-archive-keyring.gpg (@KEYRING@
# in SOURCE_LINE) and the source line to /etc/apt/sources.list.d/NAME.list.
# Only when no NAME.list or NAME.sources exists yet, so a repository the
# package manages itself afterwards (Slack) is left alone.
install_apt_repo() {
    local name=$1 key_url=$2 line=$3 keyring="/usr/share/keyrings/$1-archive-keyring.gpg"
    local list="/etc/apt/sources.list.d/$1.list"
    curl -fsSL --max-time "$lookup_timeout" -o key "$key_url"
    if grep -q 'BEGIN PGP' key; then
        gpg --dearmor <key >key.gpg
    else
        mv key key.gpg
    fi
    # A bad download (empty file, HTML error page) must not become a keyring
    # and source list that break every apt update from then on.
    gpg --show-keys key.gpg >/dev/null
    sudo install -m644 key.gpg "$keyring"
    echo "${line//@KEYRING@/$keyring}" | sudo tee "$list" >/dev/null
    # Refresh only this source. A repository with no release for this Ubuntu
    # version (a vendor lagging a release upgrade) would otherwise make every
    # later apt update fail, so it's removed again and retried next run.
    if ! apt_get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- \
        -o APT::Get::List-Cleanup=0 >/dev/null; then
        sudo rm -f "$list" "$keyring"
        echo "$name: apt can't use the repository (no release for $distro_codename?), removed it again" >&2
        return 1
    fi
}
add_apt_repo() {
    if [ ! -e "/etc/apt/sources.list.d/$1.list" ] && [ ! -e "/etc/apt/sources.list.d/$1.sources" ]; then
        step "Adding the $1 apt repository..."
        try "$1 apt repository (retried next run)" in_temp_dir install_apt_repo "$@"
    fi
}
distro_codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
add_apt_repo docker https://download.docker.com/linux/ubuntu/gpg \
    "deb [arch=amd64 signed-by=@KEYRING@] https://download.docker.com/linux/ubuntu $distro_codename stable"
add_apt_repo slack https://packagecloud.io/slacktechnologies/slack/gpgkey \
    "deb [signed-by=@KEYRING@] https://packagecloud.io/slacktechnologies/slack/debian/ jessie main"
add_apt_repo tailscale "https://pkgs.tailscale.com/stable/ubuntu/$distro_codename.noarmor.gpg" \
    "deb [signed-by=@KEYRING@] https://pkgs.tailscale.com/stable/ubuntu $distro_codename main"
add_apt_repo nordvpn-app https://repo.nordvpn.com/gpg/nordvpn_public.asc \
    "deb [signed-by=@KEYRING@] https://repo.nordvpn.com/deb/nordvpn/debian stable main"
add_apt_repo dropbox https://linux.dropbox.com/fedora/rpm-public-key.asc \
    "deb [arch=amd64 signed-by=@KEYRING@] http://linux.dropbox.com/ubuntu $distro_codename main"

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
    caffeine
    clang
    clangd
    clang-format
    cmake
    corectrl
    curl
    default-jdk
    deluge
    direnv
    suckless-tools # provides dmenu
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    dropbox
    dsniff
    dh-autoreconf
    editorconfig
    eza
    fonts-symbola
    ffmpeg
    flameshot
    flatpak # WhatsApp (ZapZap), Bottles and Lutris come from Flathub
    gawk
    g++
    g++-14
    gh
    git
    git-crypt # decrypts the encrypted dotfiles (see ~/.gitattributes)
    gnupg
    graphviz
    glslang-tools
    htop
    ibus-table-cangjie3
    ibus-table-cangjie5
    ibus-table-cangjie-big
    m17n-db
    i3lock
    xss-lock # locks before sleep / on loginctl lock-session (xmonad startup hook)
    imagemagick
    isync
    jq
    libcli11-dev # ueberzugpp (otherwise fetched at build time)
    libfmt-dev # ueberzugpp
    nlohmann-json3-dev # ueberzugpp (otherwise fetched at build time)
    librange-v3-dev # ueberzugpp (otherwise fetched at build time)
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
    lm-sensors
    lxappearance
    lxc
    maildir-utils
    meson
    m4
    mysql-client
    nasm
    net-tools
    ninja-build
    ncdu
    nitrogen
    nordvpn
    nordvpn-gui
    pandoc
    pavucontrol
    pcmanfm
    pipx
    poppler-utils
    postgresql-client
    pkg-config
    playerctl
    pulseaudio
    pulseaudio-utils
    pulseaudio-module-bluetooth
    pipenv
    protobuf-compiler
    python3
    python3-netifaces
    python3-pip
    python3-pymysql
    qemu-user
    ranger
    rofi
    shellcheck
    slack-desktop
    speedtest-cli
    tailscale
    texinfo
    texlive-full
    tidy
    tmux
    tree
    unrar
    unzip
    valgrind
    vim
    vlc
    xwallpaper
    xclip
    xfce4-power-manager
    xournalpp
    xmlto
    yq
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
# failed) would make the whole install fail; report it instead. grep reads
# the whole output on purpose: with pipefail, grep -q quitting early gives
# apt-cache a broken pipe and the check fails for every package.
apt_installable=()
for pkg in "${apt_missing[@]}"; do
    if apt-cache policy "$pkg" 2>/dev/null | grep 'Candidate: [^(]' >/dev/null; then
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


# Rust tools from crates.io; cargo builds each release once.
cargo_tool fd fd-find
cargo_tool hwatch hwatch
cargo_tool kalker kalker

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
# pnpm self-installs into $PNPM_HOME/bin, which comes first on PATH; upgrading
# the npm-installed copy would leave the one actually in use untouched.
if [ -x "$PNPM_HOME/bin/pnpm" ]; then
    step "Checking pnpm for updates..."
    if want_install pnpm "$(ver "$PNPM_HOME/bin/pnpm" --version)" "$(timeout "$lookup_timeout" npm view @pnpm/exe version 2>/dev/null || :)"; then
        try pnpm "$PNPM_HOME/bin/pnpm" self-update
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
    ! rustup component list --installed 2>/dev/null | grep '^rust-analyzer' >/dev/null; then
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

# Go tools: the list lives in go-utils.sh ("go install [flags] PKG@latest"
# lines). Each is installed if missing and offered for upgrade when its
# module has a newer release.
while read -ra go_args; do
    go_tool "${go_args[@]}"
done < <(sed -nE 's/^go install (.*)@latest.*/\1/p' ~/scripts/go-utils.sh)

if [ ! -d "$HOME/.diff-so-fancy" ]; then
    step "Installing diff-so-fancy..."
    git clone https://github.com/so-fancy/diff-so-fancy.git "$HOME/.diff-so-fancy"
else
    git_repo_update diff-so-fancy "$HOME/.diff-so-fancy"
fi

# zsh-autopair: sourced by .zshrc.
if [ ! -d "$HOME/.zsh-autopair" ]; then
    step "Installing zsh-autopair..."
    git clone https://github.com/hlissner/zsh-autopair.git "$HOME/.zsh-autopair"
else
    git_repo_update zsh-autopair "$HOME/.zsh-autopair"
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

# ---------------------------------------------------------------------------
# Prebuilt release binaries (no package or repository): system-wide ones go
# to /usr/local/bin, personal ones to ~/.local/bin.
# ---------------------------------------------------------------------------

step "Checking kubectl for updates..."
kubectl_latest="$(curl -fsS --max-time "$lookup_timeout" https://dl.k8s.io/release/stable.txt 2>/dev/null |
    grep -xE 'v[0-9]+(\.[0-9]+)*' || :)"
install_kubectl() {
    curl -fsSLO "https://dl.k8s.io/release/$kubectl_latest/bin/linux/amd64/kubectl"
    sudo install -m755 kubectl /usr/local/bin/kubectl
}
if want_install kubectl "$(ver kubectl version --client)" "$kubectl_latest" need_latest; then
    step "Installing kubectl $kubectl_latest..."
    try kubectl in_temp_dir install_kubectl
fi

# krew (kubectl plugin manager, in ~/.krew) and the plugins in use. "krew
# upgrade" updates krew itself together with every installed plugin; it's
# offered when krew or any plugin has a newer release.
if command -v kubectl >/dev/null; then
    step "Checking krew for updates..."
    krew_latest="$(latest_tag https://github.com/kubernetes-sigs/krew.git)"
    krew_current="$(kubectl krew version 2>/dev/null | awk '$1 == "GitTag" {print $2}' || :)"
    install_krew() {
        curl -fsSL "https://github.com/kubernetes-sigs/krew/releases/download/$krew_latest/krew-linux_amd64.tar.gz" | tar xz
        ./krew-linux_amd64 install krew
    }
    if want_install krew "$krew_current" "$krew_latest" need_latest; then
        if [ -z "$krew_current" ]; then
            step "Installing krew $krew_latest..."
            try krew in_temp_dir install_krew
        else
            step "Upgrading krew and its plugins..."
            try krew kubectl krew upgrade
        fi
    fi
    if command -v kubectl-krew >/dev/null; then
        krew_installed="$(kubectl krew list 2>/dev/null | awk '{print $1}' || :)"
        for plugin in ctx ns oidc-login; do
            if ! grep -qxF "$plugin" <<<"$krew_installed"; then
                step "Installing krew plugin $plugin..."
                try "krew plugin $plugin" kubectl krew install "$plugin"
            fi
        done
        # Plugin updates: refresh the index, then compare each installed
        # plugin's receipt (what's installed) with the index (what's available).
        step "Checking krew plugins for updates..."
        if timeout "$lookup_timeout" kubectl krew update >/dev/null 2>&1; then
            krew_outdated=()
            for receipt in "$HOME"/.krew/receipts/*.yaml; do
                [ -e "$receipt" ] || continue # no receipts: the glob stays literal
                plugin="$(basename "$receipt" .yaml)"
                [ "$plugin" != krew ] || continue
                installed="$(sed -n 's/^  version: //p' "$receipt" | head -1)"
                available="$(sed -n 's/^  version: //p' "$HOME/.krew/index/default/plugins/$plugin.yaml" 2>/dev/null | head -1 || :)"
                if [ -n "$available" ] && is_newer "$available" "$installed"; then
                    krew_outdated+=("$plugin $installed -> $available")
                fi
            done
            if [ ${#krew_outdated[@]} -gt 0 ] &&
                confirm "krew plugins: new versions available (${krew_outdated[*]}). Do you want to upgrade?"; then
                step "Upgrading krew plugins..."
                try "krew plugins" kubectl krew upgrade
            fi
        else
            echo "krew: could not refresh the plugin index, skipping the plugin update check" >&2
        fi
    fi
fi

step "Checking k9s for updates..."
k9s_latest="$(latest_tag https://github.com/derailed/k9s.git)"
install_k9s() {
    curl -fsSL "https://github.com/derailed/k9s/releases/download/$k9s_latest/k9s_Linux_amd64.tar.gz" | tar xz
    sudo install -m755 k9s /usr/local/bin/k9s
}
if want_install k9s "$(ver k9s version -s)" "$k9s_latest" need_latest; then
    step "Installing k9s $k9s_latest..."
    try k9s in_temp_dir install_k9s
fi

step "Checking golangci-lint for updates..."
golangci_latest="$(latest_tag https://github.com/golangci/golangci-lint.git)"
install_golangci_lint() {
    curl -fsSL "https://github.com/golangci/golangci-lint/releases/download/$golangci_latest/golangci-lint-${golangci_latest#v}-linux-amd64.tar.gz" | tar xz
    sudo install -m755 golangci-lint-*/golangci-lint /usr/local/bin/golangci-lint
}
if want_install golangci-lint "$(ver golangci-lint --version)" "$golangci_latest" need_latest; then
    step "Installing golangci-lint $golangci_latest..."
    try golangci-lint in_temp_dir install_golangci_lint
fi

step "Checking grype for updates..."
grype_latest="$(latest_tag https://github.com/anchore/grype.git)"
install_grype() {
    curl -fsSL "https://github.com/anchore/grype/releases/download/$grype_latest/grype_${grype_latest#v}_linux_amd64.tar.gz" | tar xz
    sudo install -m755 grype /usr/local/bin/grype
}
if want_install grype "$(ver grype version)" "$grype_latest" need_latest; then
    step "Installing grype $grype_latest..."
    try grype in_temp_dir install_grype
fi

# AWS CLI v2: the official installer puts it in /usr/local/aws-cli and links
# aws into /usr/local/bin. The repository's newest tag is the latest release.
step "Checking aws cli for updates..."
aws_latest="$(latest_tag https://github.com/aws/aws-cli.git)"
install_aws() {
    curl -fsSLo awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
    unzip -q awscliv2.zip
    sudo ./aws/install --update
}
if want_install "aws cli" "$(ver aws --version)" "$aws_latest"; then
    step "Installing aws cli $aws_latest..."
    try "aws cli" in_temp_dir install_aws
fi

step "Checking age for updates..."
age_latest="$(latest_tag https://github.com/FiloSottile/age.git)"
install_age() {
    curl -fsSL "https://github.com/FiloSottile/age/releases/download/$age_latest/age-$age_latest-linux-amd64.tar.gz" | tar xz
    mkdir -p ~/.local/bin
    install -m755 age/age age/age-keygen ~/.local/bin/
}
if want_install age "$(ver age --version)" "$age_latest" need_latest; then
    step "Installing age $age_latest..."
    try age in_temp_dir install_age
fi

step "Checking sops for updates..."
sops_latest="$(latest_tag https://github.com/getsops/sops.git)"
install_sops() {
    curl -fsSLo sops "https://github.com/getsops/sops/releases/download/$sops_latest/sops-$sops_latest.linux.amd64"
    mkdir -p ~/.local/bin
    install -m755 sops ~/.local/bin/sops
}
if want_install sops "$(ver sops --version)" "$sops_latest" need_latest; then
    step "Installing sops $sops_latest..."
    try sops in_temp_dir install_sops
fi

# ueberzugpp (image previews in yazi): built from the latest release into
# /usr/local, with the X11 and OpenCV backends.
step "Checking ueberzugpp for updates..."
ueberzugpp_latest="$(latest_tag https://github.com/jstkdng/ueberzugpp.git)"
build_ueberzugpp() {
    cmake -DCMAKE_BUILD_TYPE=Release -DENABLE_OPENCV=ON -B build
    cmake --build build -j "$(nproc)"
    sudo cmake --install build
}
if want_install ueberzugpp "$(ver ueberzugpp --version)" "$ueberzugpp_latest" need_latest; then
    step "Building ueberzugpp $ueberzugpp_latest (can take a while)..."
    try ueberzugpp build_from_tag https://github.com/jstkdng/ueberzugpp.git "$ueberzugpp_latest" build_ueberzugpp
fi

# kmonad remaps the laptop's built-in keyboard (xmonad.hs starts it with
# lenovo.kbd), so it's only set up on a laptop (or 2-in-1): the static release binary,
# plus access to /dev/uinput, which is root-only by default. The udev rule
# and uinput group below open it to this user, as in kmonad's FAQ; the group
# membership takes effect at the next login.
install_kmonad() {
    curl -fsSLo kmonad "https://github.com/kmonad/kmonad/releases/download/$kmonad_latest/kmonad"
    sudo install -m755 kmonad /usr/local/bin/kmonad
}
setup_uinput() {
    getent group uinput >/dev/null || sudo groupadd uinput
    sudo usermod -aG input,uinput "$(id -un)"
    echo uinput | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
    sudo modprobe uinput
    echo 'KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"' |
        sudo tee /etc/udev/rules.d/90-uinput.rules >/dev/null
    sudo udevadm control --reload-rules
    sudo udevadm trigger --name-match=uinput
}
case "$(hostnamectl chassis 2>/dev/null)" in laptop | convertible) kmonad_wanted=1 ;; *) kmonad_wanted=0 ;; esac
if [ "$kmonad_wanted" = 1 ]; then
    step "Checking kmonad for updates..."
    kmonad_latest="$(latest_tag https://github.com/kmonad/kmonad.git)"
    if want_install kmonad "$(ver kmonad --version)" "$kmonad_latest" need_latest; then
        step "Installing kmonad $kmonad_latest..."
        try kmonad in_temp_dir install_kmonad
    fi
    if [ ! -f /etc/udev/rules.d/90-uinput.rules ]; then
        step "Setting up uinput access for kmonad (log in again for it to apply)..."
        try "kmonad uinput setup" setup_uinput
    fi
fi

# umu-launcher (runs Windows games under Proton, used by the battlenet
# script): the zipapp release, one self-contained file.
step "Checking umu-launcher for updates..."
umu_latest="$(latest_tag https://github.com/Open-Wine-Components/umu-launcher.git)"
install_umu() {
    curl -fsSL "https://github.com/Open-Wine-Components/umu-launcher/releases/download/$umu_latest/umu-launcher-$umu_latest-zipapp.tar" | tar x
    mkdir -p ~/.local/bin
    install -m755 umu/umu-run ~/.local/bin/umu-run
}
if want_install umu-launcher "$(ver umu-run --version)" "$umu_latest" need_latest; then
    step "Installing umu-launcher $umu_latest..."
    try umu-launcher in_temp_dir install_umu
fi

# GalaxyBudsClient: the portable binary in ~/.local/bin plus a launcher
# entry. It has no --version flag, so the installed version is recorded in a
# marker file.
step "Checking galaxy buds client for updates..."
gbc_latest="$(latest_tag https://github.com/timschneeb/GalaxyBudsClient.git)"
gbc_bin="$HOME/.local/bin/GalaxyBudsClient.bin"
gbc_marker="${XDG_STATE_HOME:-$HOME/.local/state}/galaxybudsclient-version"
gbc_current=""
if [ -x "$gbc_bin" ]; then
    gbc_current="$(grep -xE '[0-9]+(\.[0-9]+)*' "$gbc_marker" 2>/dev/null || echo "0 (unknown)")"
fi
install_gbc() {
    local apps="$HOME/.local/share/applications" icons="$HOME/.local/share/icons"
    curl -fsSLo GalaxyBudsClient.bin \
        "https://github.com/timschneeb/GalaxyBudsClient/releases/download/$gbc_latest/GalaxyBudsClient_Linux_64bit_Portable.bin"
    mkdir -p ~/.local/bin "$apps" "$icons"
    # install(1) replaces the file instead of writing into it, so this also
    # works while the app is running ("Text file busy" otherwise).
    install -m755 GalaxyBudsClient.bin "$gbc_bin"
    curl -fsSLo "$icons/galaxybudsclient.png" \
        https://raw.githubusercontent.com/timschneeb/GalaxyBudsClient/master/GalaxyBudsClient/Resources/icon_small.png || :
    cat >"$apps/galaxybudsclient.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Galaxy Buds Client
Comment=Unofficial manager for Samsung Galaxy Buds
Exec=$gbc_bin
Icon=$icons/galaxybudsclient.png
Terminal=false
Categories=Utility;AudioVideo;
Keywords=galaxy;buds;samsung;earbuds;bluetooth;
StartupWMClass=GalaxyBudsClient
DESKTOP
    update-desktop-database "$apps" 2>/dev/null || :
    mkdir -p "$(dirname "$gbc_marker")"
    echo "$gbc_latest" >"$gbc_marker"
}
if want_install "galaxy buds client" "$gbc_current" "$gbc_latest" need_latest; then
    step "Installing galaxy buds client $gbc_latest..."
    try "galaxy buds client" in_temp_dir install_gbc
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
viber_latest="$(curl -fsS --max-time "$lookup_timeout" -r 0-262143 "$viber_url" 2>/dev/null |
    dpkg-deb -f /dev/stdin Version 2>/dev/null || :)"
if want_install viber "$(deb_version viber)" "$viber_latest" need_latest; then
    step "Installing viber $viber_latest..."
    try viber in_temp_dir install_deb "$viber_url"
fi

# Google Chrome: the official .deb. Installing it sets up Google's apt
# repository, which keeps it updated from then on.
if [ -z "$(deb_version google-chrome-stable)" ]; then
    step "Installing google chrome..."
    try "google chrome" in_temp_dir install_deb \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
fi

# Discord and Zoom: official .debs with no apt repository. Their "latest"
# download URLs redirect to a versioned one, which gives the latest version
# without downloading the package.
step "Checking discord for updates..."
discord_url="https://discord.com/api/download?platform=linux&format=deb"
discord_latest="$(curl -fsS --max-time "$lookup_timeout" -o /dev/null -w '%{redirect_url}' "$discord_url" 2>/dev/null |
    sed -nE 's|.*/discord-([0-9]+(\.[0-9]+)*)\.deb$|\1|p' || :)"
if want_install discord "$(deb_version discord)" "$discord_latest" need_latest; then
    step "Installing discord $discord_latest..."
    try discord in_temp_dir install_deb "$discord_url"
fi

step "Checking zoom for updates..."
zoom_url="https://zoom.us/client/latest/zoom_amd64.deb"
zoom_latest="$(curl -fsS --max-time "$lookup_timeout" -o /dev/null -w '%{redirect_url}' "$zoom_url" 2>/dev/null |
    sed -nE 's|.*/prod/([0-9]+(\.[0-9]+)*)/.*|\1|p' || :)"
if want_install zoom "$(deb_version zoom)" "$zoom_latest" need_latest; then
    step "Installing zoom $zoom_latest..."
    try zoom in_temp_dir install_deb "$zoom_url"
fi

# LocalSend: the .deb from its GitHub releases (no apt repository).
step "Checking localsend for updates..."
localsend_latest="$(latest_tag https://github.com/localsend/localsend.git)"
if want_install localsend "$(deb_version localsend)" "$localsend_latest" need_latest; then
    step "Installing localsend $localsend_latest..."
    try localsend in_temp_dir install_deb \
        "https://github.com/localsend/localsend/releases/download/$localsend_latest/LocalSend-${localsend_latest#v}-linux-x86-64.deb"
fi

# Plex Media Server: the .deb from Plex's downloads API (the package ships
# an apt source, but disabled). Version and URL come in one step, both empty
# if either is missing.
step "Checking plex for updates..."
IFS=$'\t' read -r plex_latest plex_url < <(curl -fsS --max-time "$lookup_timeout" \
    https://plex.tv/api/downloads/5.json 2>/dev/null |
    jq -r '.computer.Linux | .version as $v
        | first(.releases[] | select(.build == "linux-x86_64" and .distro == "debian"))
        | select($v != null and .url != null)
        | [$v, .url] | @tsv' 2>/dev/null) || :
if want_install plex "$(deb_version plexmediaserver)" "$plex_latest" need_latest; then
    step "Installing plex $plex_latest..."
    try plex in_temp_dir install_deb "$plex_url"
fi

# calibre: the official installer (binary build into /opt/calibre).
step "Checking calibre for updates..."
calibre_latest="$(latest_tag https://github.com/kovidgoyal/calibre.git)"
if want_install calibre "$(ver calibre --version)" "$calibre_latest"; then
    step "Installing calibre ${calibre_latest#v}..."
    install_calibre() {
        curl -fsSL --max-time 60 https://download.calibre-ebook.com/linux-installer.sh | sudo sh /dev/stdin
    }
    try calibre install_calibre
fi

# Flathub apps, installed for this user (no sudo). WhatsApp has no official
# Linux app: ZapZap is a maintained desktop client for WhatsApp Web.
timeout "$lookup_timeout" flatpak remote-add --user --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo || :
flatpak_app "whatsapp (ZapZap)" com.rtosta.zapzap
flatpak_app bottles com.usebottles.bottles
flatpak_app lutris net.lutris.Lutris

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
