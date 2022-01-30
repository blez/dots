#!/usr/bin/env bash
set -euo pipefail

gen_list() {
    IFS=$'\n'
    endpoints=()

    for i in $(nmcli d wifi list --rescan yes | awk '(NR>1)'); do
        if [[ $i =~ ^\*.* ]]; then
            endpoints+=("$(echo "$i" | awk '{print $1,$3,$6,$7}')")
        else
            endpoints+=("$(echo "$i" | awk '{print $2,$5,$6}')")
        fi
    done

    for i in "${endpoints[@]}"; do
        echo "$i"
    done
}

main() {
    eps=$( (gen_list) | rofi -dmenu -matching fuzzy -no-custom -location 0 -i -p "Available WiFi endpoints")

    if [ -n "$eps" ]; then
        if echo "$eps" | grep -q '\*'; then
            nmcli c down "$(echo "$eps" | awk '{print $2}')"

            notify-send --app-name "Rofi" "Disconnected from $eps"
        else
            passwd=$(~/.config/rofi/askpass.sh)

            nmcli d wifi connect "$(echo "$eps" | awk '{print $1}')" password "$passwd" ||
                notify-send --app-name "Rofi" "Failed to connect"

            notify-send --app-name "Rofi" "Connected to $eps"
        fi
    else
        exit
    fi
}

main

exit 0
