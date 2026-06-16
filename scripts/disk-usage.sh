#!/usr/bin/env bash
# Prints root filesystem usage percentage for xmobar, e.g. "53%".
df -h / 2>/dev/null | awk 'NR==2 {print $5}'
