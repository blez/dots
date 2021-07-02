#!/usr/bin/env bash

if nmcli connection show --active | awk 'NR>1 {print $3}' | grep -q vpn; then
    nmcli connection show --active | awk 'NR>1 {print $1, $3}' | grep vpn | awk '{print $1}'
else
    echo "x"
fi
