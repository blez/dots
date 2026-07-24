#!/usr/bin/env bash
set -euo pipefail

# Minimal rofi Bluetooth menu — mirrors ~/scripts/blue-tui.sh.
# Just the device list: Enter toggles connect/disconnect. One entry to
# scan & pair something new. Audio devices get routed automatically.

rofi_cmd() { rofi -dmenu -i -matching fuzzy -no-custom "$@"; }

notify() { command -v notify-send >/dev/null && notify-send --app-name "Bluetooth" "$@" || true; }

connected() { bluetoothctl info "$1" | grep -q "Connected: yes"; }

# Make a freshly-connected audio device the default output (fixes the
# "connected but sound stays on laptop" case).
route_audio() {
    local mac="$1" sink="bluez_output.${1//:/_}.1"
    for _ in $(seq 1 8); do
        pactl list short sinks 2>/dev/null | grep -q "$sink" && break
        sleep 1
    done
    pactl list short sinks 2>/dev/null | grep -q "$sink" || return 0
    pactl set-default-sink "$sink" 2>/dev/null || return 0
    for id in $(pactl list short sink-inputs 2>/dev/null | awk '{print $1}'); do
        pactl move-sink-input "$id" "$sink" 2>/dev/null || true
    done
}

toggle() {
    local mac="$1" name="$2"
    if connected "$mac"; then
        bluetoothctl disconnect "$mac" >/dev/null && notify "Disconnected $name"
    else
        notify "Connecting $name…"
        if bluetoothctl connect "$mac" >/dev/null; then
            route_audio "$mac"
            notify "Connected $name"
        else
            notify "Failed to connect $name"
        fi
    fi
}

scan_and_pair() {
    notify "Scanning 10s…" "Put the device in pairing mode"
    bluetoothctl --timeout 10 scan on >/dev/null 2>&1 || true
    local paired new pick mac
    paired=$(bluetoothctl devices Paired | awk '{print $2}')
    # discovered devices that aren't already paired and have a real name
    new=$(bluetoothctl devices | grep -vFf <(echo "$paired") 2>/dev/null | grep -v "^Device [0-9A-F:]* [0-9A-F:]*$" || true)
    [[ -z "$new" ]] && { notify "Nothing new found"; return; }
    pick=$(cut -d ' ' -f 3- <<< "$new" | rofi_cmd -p "Pair") || return
    [[ -z "$pick" ]] && return
    mac=$(grep -F "$pick" <<< "$new" | head -1 | awk '{print $2}')
    [[ -z "$mac" ]] && return
    notify "Pairing $pick…"
    if bluetoothctl pair "$mac" >/dev/null && bluetoothctl trust "$mac" >/dev/null && bluetoothctl connect "$mac" >/dev/null; then
        route_audio "$mac"
        notify "Paired & connected $pick"
    else
        notify "Pairing failed" "$pick"
    fi
}

menu() {
    bluetoothctl show | grep -q "Powered: yes" || bluetoothctl power on >/dev/null

    declare -A byline=()
    local lines=()
    while read -r _ mac name; do
        [[ -z "${mac:-}" ]] && continue
        if connected "$mac"; then icon="󰂱"; else icon="󰂯"; fi
        local line="$icon  $name"
        byline["$line"]="$mac"
        lines+=("$line")
    done < <(bluetoothctl devices Paired)

    local scan_entry="󰐗  Scan & pair new…"
    local chosen
    chosen=$(printf '%s\n' "${lines[@]}" "$scan_entry" | rofi_cmd -p "Bluetooth") || exit 0
    [[ -z "$chosen" ]] && exit 0

    if [[ "$chosen" == "$scan_entry" ]]; then
        scan_and_pair
    else
        local mac="${byline[$chosen]:-}"
        [[ -z "$mac" ]] && exit 0
        toggle "$mac" "${chosen#*  }"
    fi
    menu   # loop back so it feels continuous
}

menu
