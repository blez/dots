#!/bin/bash
set -eu

if [ -z "$(ls -A /sys/class/power_supply)" ]; then
    exit 0
fi

mapfile -t devices < <(busctl tree 'org.bluez' | grep -Eo "dev_.+" | grep -v '/')

names=()
for i in "${devices[@]}"; do
    connected="$(busctl introspect 'org.bluez' "/org/bluez/hci0/$i" | grep .Connected | grep true | awk '(NR<2)')"
    if [[ -n "$connected" ]]; then
        name="$(busctl introspect 'org.bluez' "/org/bluez/hci0/$i" | grep .Alias | grep -Eo '".+"' | cut -d\" -f2)"
        names+=("$name")
    fi
done

if ((${#names[@]})); then
    echo "${names[*]}"
else
    echo "x"
fi
