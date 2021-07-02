#!/usr/bin/env bash
set -euo pipefail

gen_list() {
    nmcli connection show | grep -i vpn | awk '{print $1,$4}'
}

main() {
    vpn=$( (gen_list) | rofi -dmenu -matching fuzzy -no-custom -location 0 -i -p "Available VPN")

    if [ -n "$vpn" ]; then
        if echo "$vpn" | grep -q "\\-\\-"; then
            nmcli connection up "$(echo "$vpn" | awk '{print $1}')"
        else
            nmcli connection down "$(echo "$vpn" | awk '{print $1}')"
        fi
    else
        exit
    fi
}

main

exit 0
