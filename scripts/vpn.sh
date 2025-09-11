#!/usr/bin/env bash

vpn=$(nmcli connection show --active | awk 'NR>1 {print $3}' | grep -q vpn)
nordvpn=$(nordvpn status | grep "Server: ")

if [[ -n "$vpn" ]]; then
    echo "$vpn" | awk '{print $1}'
elif [[ -n "$nordvpn" ]]; then
    echo "$nordvpn" | awk '{print $2}'
else
    echo "x"
fi
