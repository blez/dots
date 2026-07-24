#!/usr/bin/env bash
set -euo pipefail

# Installs / updates GalaxyBudsClient (portable Linux binary) from GitHub releases.
# https://github.com/timschneeb/GalaxyBudsClient

bin_dir="$HOME/.local/bin"
apps_dir="$HOME/.local/share/applications"
icons_dir="$HOME/.local/share/icons"
bin_path="$bin_dir/GalaxyBudsClient.bin"

url=$(curl -s https://api.github.com/repos/timschneeb/GalaxyBudsClient/releases/latest |
    jq -r '.assets[] | select(.name == "GalaxyBudsClient_Linux_64bit_Portable.bin") | .browser_download_url')

if [[ -z "$url" || "$url" == "null" ]]; then
    echo "Could not find the Linux 64-bit portable asset in the latest release" >&2
    exit 1
fi

mkdir -p "$bin_dir" "$apps_dir" "$icons_dir"

# Download to a temp file and move into place, so an update works even while
# the app is running ("Text file busy" otherwise).
tmp_bin=$(mktemp "$bin_dir/GalaxyBudsClient.bin.XXXXXX")
trap 'rm -f "$tmp_bin"' EXIT
curl -L --fail -o "$tmp_bin" "$url"
chmod +x "$tmp_bin"
mv -f "$tmp_bin" "$bin_path"

curl -L --fail -s -o "$icons_dir/galaxybudsclient.png" \
    https://raw.githubusercontent.com/timschneeb/GalaxyBudsClient/master/GalaxyBudsClient/Resources/icon_small.png || true

cat > "$apps_dir/galaxybudsclient.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Galaxy Buds Client
Comment=Unofficial manager for Samsung Galaxy Buds
Exec=$bin_path
Icon=$icons_dir/galaxybudsclient.png
Terminal=false
Categories=Utility;AudioVideo;
Keywords=galaxy;buds;samsung;earbuds;bluetooth;
StartupWMClass=GalaxyBudsClient
EOF

update-desktop-database "$apps_dir" 2>/dev/null || true

version=$(awk -F '/' '{print $8}' <<< "$url")
echo "GalaxyBudsClient was updated to $version"
