#!/usr/bin/env bash
set -euo pipefail

WORKINGDIR="$HOME/.config/rofi/"
MAP="$WORKINGDIR/cmd.csv"

cut -d ',' -f 1 "$MAP" |
    rofi -dmenu -matching fuzzy -no-custom -i -p "Util " |
    head -n 1 |
    xargs -i --no-run-if-empty grep "{}" "$MAP" |
    cut -d ',' -f 2 |
    head -n 1 |
    xargs -i --no-run-if-empty /bin/bash -c "{}"

exit 0
