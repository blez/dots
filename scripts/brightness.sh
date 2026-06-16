#!/usr/bin/env bash
# Prints screen brightness as a percentage for xmobar, e.g. "80%".
# No-ops (prints nothing) on machines without a backlight, e.g. a desktop.
shopt -s nullglob
for dev in /sys/class/backlight/*; do
    cur=$(cat "$dev/brightness" 2>/dev/null) || continue
    max=$(cat "$dev/max_brightness" 2>/dev/null) || continue
    [ -n "$max" ] && [ "$max" -gt 0 ] || continue
    printf '%d%%\n' $(( cur * 100 / max ))
    exit 0
done
