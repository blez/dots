#!/usr/bin/env bash

# Take password prompt from STDIN, print password to STDOUT
# the sed piece just removes the colon from the provided
# prompt: rofi -p already gives us a colon
rofi -dmenu \
    -password \
    -no-fixed-num-lines \
    -p "Password $(printf '%s' "$1" | sed s/.*Password://)"
