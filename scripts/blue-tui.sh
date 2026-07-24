#!/usr/bin/env bash
set -euo pipefail

# Minimal Bluetooth manager on top of bluetoothctl + fzf.
#   Enter    connect / disconnect the selected device (toggles)
#   ctrl-s   scan ~10s and pair a newly found device
#   ctrl-t   toggle trust (auto-reconnect on boot)
#   ctrl-x   remove (unpair) the selected device
#   ctrl-r   refresh the list
#   esc      quit

adapter_up() {
    bluetoothctl show | grep -q "Powered: yes" || bluetoothctl power on >/dev/null
}

# Prints one line per paired device: "<mark> <name>\t<MAC>"
list_devices() {
    while read -r _ mac name; do
        [[ -z "${mac:-}" ]] && continue
        if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
            mark=""      # connected
        else
            mark="○"      # known, not connected
        fi
        printf '%s %s\t%s\n' "$mark" "$name" "$mac"
    done < <(bluetoothctl devices Paired)
}

mac_of()  { awk -F'\t' '{print $2}' <<< "$1"; }
name_of() { awk -F'\t' '{print $1}' <<< "$1" | sed 's/^[●○] //'; }

toggle_connect() {
    local mac="$1"
    if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
        echo "Disconnecting $mac ..."
        bluetoothctl disconnect "$mac" || true
    else
        echo "Connecting $mac ..."
        bluetoothctl connect "$mac" || echo "Connect failed (is the device on / out of the case?)"
    fi
    sleep 1
}

scan_and_pair() {
    echo "Scanning ~10s — put the device in pairing mode ..."
    bluetoothctl --timeout 10 scan on >/dev/null 2>&1 || true
    local pick
    pick=$(bluetoothctl devices | grep -v "$(bluetoothctl devices Paired | awk '{print $2}' | paste -sd'|' -)" \
        | fzf --prompt="pair> " --with-nth=3.. ) || return 0
    local mac; mac=$(awk '{print $2}' <<< "$pick")
    [[ -z "$mac" ]] && return 0
    echo "Pairing $mac ..."
    bluetoothctl pair "$mac" && bluetoothctl trust "$mac" && bluetoothctl connect "$mac" || \
        echo "Pairing failed."
    sleep 1
}

toggle_trust() {
    local mac="$1"
    if bluetoothctl info "$mac" | grep -q "Trusted: yes"; then
        bluetoothctl untrust "$mac"; echo "Untrusted $mac"
    else
        bluetoothctl trust "$mac"; echo "Trusted $mac"
    fi
    sleep 1
}

remove_device() {
    local mac="$1"
    read -r -p "Remove (unpair) $mac? [y/N] " ans
    [[ "$ans" == [yY] ]] && bluetoothctl remove "$mac" && echo "Removed."
    sleep 1
}

adapter_up

while true; do
    sel=$(list_devices | fzf \
        --prompt="bluetooth> " \
        --header=$'enter connect/disconnect · ctrl-s pair new · ctrl-t trust · ctrl-x remove · ctrl-r refresh · esc quit\n● connected  ○ offline' \
        --with-nth=1 \
        --delimiter='\t' \
        --expect=ctrl-s,ctrl-t,ctrl-x,ctrl-r \
        --bind=esc:abort) || exit 0

    key=$(head -1 <<< "$sel")
    row=$(sed -n '2p' <<< "$sel")

    case "$key" in
        ctrl-s) scan_and_pair; continue ;;
        ctrl-r) continue ;;
    esac

    [[ -z "${row:-}" ]] && continue
    mac=$(mac_of "$row")

    case "$key" in
        ctrl-t) toggle_trust "$mac" ;;
        ctrl-x) remove_device "$mac" ;;
        *)      toggle_connect "$mac" ;;
    esac
done
