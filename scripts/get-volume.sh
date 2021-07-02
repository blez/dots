#!/usr/bin/env bash
set -euo pipefail

echo "$(amixer get Master | awk -F'[]%[]' '/%/ {if ($7 == "off") { print "MM" } else { print $2 }}' | head -n 1)%"
