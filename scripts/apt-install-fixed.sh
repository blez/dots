#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 <package.deb>" >&2
    exit 1
fi

package="$1"
name="$(basename "${package}" .deb)"

dpkg-deb -x "$package" "$name"
dpkg-deb --control "$package" "$name"/DEBIAN
sed -i -- 's/libappindicator3-1/libayatana-appindicator3-1/g' ./"$name"/DEBIAN/control
sed -i -- 's/libappindicator1/libayatana-appindicator1/g' ./"$name"/DEBIAN/control

new="${name}-debian.deb"
dpkg -b "$name" "$new"
rm -rf "$name"
sudo apt install ./"$new"
rm -rf ./"$new"
