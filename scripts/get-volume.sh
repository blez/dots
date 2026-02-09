#!/usr/bin/env bash
set -euo pipefail

out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)

if [[ $out == *MUTED* ]]; then
  echo "MM"
else
  awk '{printf "%d%%\n", $2*100}' <<<"$out"
fi

# echo "$(amixer get Master | awk -F'[]%[]' '/%/ {if ($7 == "off") { print "MM" } else { print $2 }}' | head -n 1)%"
