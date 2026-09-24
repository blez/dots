#!/usr/bin/env bash
# Launches xmobar with interface names detected at runtime, so the same
# xmobarrc works across machines (desktop, laptop, USB ethernet dongles).
#
# xmobarrc uses the tokens __ETH__ and __WIFI__ as placeholders (plus
# __BOX__/__XOB__ for segment styling). This script
# resolves the real interface names, writes a generated rc, then execs xmobar
# so it inherits this process's stdin (the pipe xmonad uses for StdinReader).
set -euo pipefail

CONFIG_DIR="$HOME/.config/xmobar"
TEMPLATE="$CONFIG_DIR/xmobarrc"
GENERATED="$CONFIG_DIR/xmobarrc.generated"
XMOBAR="$HOME/.cabal/bin/xmobar"

# A wireless interface has a 'wireless' subdir under /sys/class/net.
detect_wifi() {
    local dev
    for dev in /sys/class/net/*; do
        [ -d "$dev/wireless" ] && { basename "$dev"; return; }
    done
}

# A wired interface: has a device, is not wireless, and is not virtual
# (skip lo, bridges, veth, docker, tailscale, etc. — these lack a real
# 'device' symlink). Prefer one that currently has carrier (cable/link up).
detect_eth() {
    local dev name best=""
    for dev in /sys/class/net/*; do
        name=$(basename "$dev")
        [ -e "$dev/device" ] || continue   # skip virtual interfaces
        [ -d "$dev/wireless" ] && continue  # skip wifi
        best=${best:-$name}                 # remember first candidate
        if [ "$(cat "$dev/operstate" 2>/dev/null)" = "up" ]; then
            echo "$name"; return            # prefer an up link
        fi
    done
    [ -n "$best" ] && echo "$best"
}

ETH=$(detect_eth || true)
WIFI=$(detect_wifi || true)

# Shared styling for bar segments; xmobarrc writes __BOX__...__XOB__.
BOX='<box type=Bottom width=2 mb=2 color=red><fc=white>'
XOB='</fc></box>'

# Drop every line mentioning an absent interface type (its commands and its
# template segment), so a machine without wifi shows no dead wifi segment.
drop=()
[ -z "$ETH" ] && drop+=(-e '/__ETH__/d')
[ -z "$WIFI" ] && drop+=(-e '/__WIFI__/d')

sed "${drop[@]}" \
    -e "s/__ETH__/$ETH/g" -e "s/__WIFI__/$WIFI/g" \
    -e "s|__BOX__|$BOX|g" -e "s|__XOB__|$XOB|g" \
    "$TEMPLATE" > "$GENERATED"

exec "$XMOBAR" -x 0 "$GENERATED"
