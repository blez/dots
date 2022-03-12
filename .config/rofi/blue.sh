#!/usr/bin/env bash
set -euo pipefail

main() {
    declare -A devices=()

    rawDevices=$(bluetoothctl devices | awk '{$1=""; print $0}' | awk '{$1=$1;print}')

    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{$1=""; print $0}' | awk '{$1=$1;print}')

        if [ "$(bluetoothctl info "$id" | grep Connected: | awk '{print $2}')" == "yes" ]; then
            devices["* $name"]="$id"
        else
            devices["$name"]="$id"
        fi
    done <<<"$rawDevices"

    device=$( (for dev in "${!devices[@]}"; do echo "$dev"; done) | rofi -dmenu -matching fuzzy -no-custom -location 0 -i -p "Bluetooth devices")

    if [ -n "$device" ]; then
        if echo "$device" | grep -q "\*"; then
            if [[ $(bluetoothctl disconnect "${devices[$device]}") ]]; then
                notify-send --app-name "Rofi" "Disconnected from $device"
            else
                notify-send --app-name "Rofi" "Failed to disconnected from $device"
            fi
        else
            if [[ $(bluetoothctl connect "${devices[$device]}") ]]; then
                notify-send --app-name "Rofi" "Connected to $device"
            else
                notify-send --app-name "Rofi" "Failed to connected to $device"
            fi
        fi
    else
        exit
    fi
}

main

exit 0
