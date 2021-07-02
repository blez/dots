#!/usr/bin/env bash
set -euo pipefail

layout=$(setxkbmap -query | grep layout | awk 'END{print $2}')
case $layout in
us)
    setxkbmap ru
    ;;
ru)
    setxkbmap us
    ;;
*)
    setxkbmap us
    ;;
esac
