#!/usr/bin/env bash
set -euo pipefail

layout=$(setxkbmap -query | grep layout | awk 'END{print $2}')
case $layout in
us)
    setxkbmap ru
    ;;
ru)
    # both Alts type Polish characters, only while pl is active
    setxkbmap pl -option lv3:lalt_switch
    ;;
pl)
    setxkbmap us -option ''
    ;;
*)
    setxkbmap us -option ''
    ;;
esac
