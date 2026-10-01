#!/usr/bin/env bash
# Launches xmobar with interface names detected at runtime, so the same
# xmobarrc works across machines (desktop, laptop, USB ethernet dongles).
#
# xmobarrc uses the tokens __ETH__ and __WIFI__ as placeholders for interface
# names, __BAT__ and __BL__ to mark the battery and backlight segments, plus
# __BOX__/__XOB__ for segment styling. This script resolves them, writes a
# generated rc, then execs xmobar. xmonad (XMonad.Hooks.StatusBar) starts
# this script in its own process group and kills that whole group on
# restart, so xmobar must stay in it: don't detach it with setsid or "&".
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

# A laptop screen has a backlight device; desktop monitors don't.
detect_backlight() {
    compgen -G '/sys/class/backlight/*' >/dev/null && echo yes
}

# A laptop battery: type Battery, and not a peripheral's battery (wireless
# mice and headsets report scope=Device). Matches what charge-status.sh finds
# via upower.
detect_battery() {
    local dev
    for dev in /sys/class/power_supply/*; do
        [ "$(cat "$dev/type" 2>/dev/null)" = Battery ] || continue
        [ "$(cat "$dev/scope" 2>/dev/null)" = Device ] && continue
        echo yes; return
    done
}

ETH=$(detect_eth || true)
WIFI=$(detect_wifi || true)
BACKLIGHT=$(detect_backlight || true)
BATTERY=$(detect_battery || true)

# Shared styling for bar segments; xmobarrc writes __BOX__...__XOB__.
BOX='<box type=Bottom width=2 mb=2 color=red><fc=white>'
XOB='</fc></box>'

# Drop every line mentioning absent hardware (its commands and its template
# segment), so a machine without wifi or a backlight shows no dead segment.
drop=()
[ -z "$ETH" ] && drop+=(-e '/__ETH__/d')
[ -z "$WIFI" ] && drop+=(-e '/__WIFI__/d')
[ -z "$BACKLIGHT" ] && drop+=(-e '/__BL__/d')
[ -z "$BATTERY" ] && drop+=(-e '/__BAT__/d')

sed "${drop[@]}" \
    -e "s/__ETH__/$ETH/g" -e "s/__WIFI__/$WIFI/g" -e "s/__BL__//g" -e "s/__BAT__//g" \
    -e "s|__BOX__|$BOX|g" -e "s|__XOB__|$XOB|g" \
    "$TEMPLATE" > "$GENERATED"

exec "$XMOBAR" -x 0 "$GENERATED"
