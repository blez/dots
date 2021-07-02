#!/bin/bash
set -euo pipefail

cmd=$1

mapfile -t devices < <(bt-device -l | awk '{if(NR>1)print}')

for i in "${devices[@]}"; do
    mac=$(echo "$i" | awk '{print $NF}' | sed 's/[\(\)]//g; s/\:/_/g')

    dbus-send --system --print-reply --dest=org.bluez "/org/bluez/hci0/dev_$mac" \
        "org.bluez.MediaControl1.${cmd^}" \
        >/dev/null 2>&1 &&
        echo "${cmd^} $i"
done
