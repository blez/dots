#!/usr/bin/env bash
set -euo pipefail

case $1 in
play)
    playerctl play-pause
    ;;
next)
    playerctl next
    sleep 1
    ;;
prev)
    playerctl previous
    sleep 1
    ;;
esac

notify-send -a "Music" "$(playerctl metadata --format "{{ artist }} - {{ title }} ({{status}})")"
