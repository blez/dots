#!/usr/bin/env bash
set -euo pipefail

state=$(upower -i "$(upower -e | grep 'BAT')" | grep state | awk '{print $2}')
percent=$(upower -i "$(upower -e | grep 'BAT')" | grep -E "percentage" | awk '{print $2}')
percent=${percent%$"%"}

charge_image=""
if [ "$state" = "charging" ]; then
    charge_image=$'\uf0e7 '
elif [ "$state" = "discharging" ]; then
    charge_image=$'\uf071 '
elif [ "$state" = "pending-charge" ]; then
    charge_image=$'\uf28b '
fi

batery_image=""
if [[ "$percent" == 100 ]]; then
    batery_image=$'\uf240'
elif ((percent < 100 && percent >= 75)); then
    batery_image=$'\uf241'
elif ((percent < 75 && percent >= 50)); then
    batery_image=$'\uf242'
elif ((percent < 50 && percent >= 25)); then
    batery_image=$'\uf243'
else
    batery_image=$'\uf244'
fi

echo "$charge_image$batery_image $percent%"
