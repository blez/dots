#!/usr/bin/env bash
# Prints a short VPN status string for xmobar, or "x" when no VPN is active.
# Checks, in order: NetworkManager VPN/WireGuard connections, Tailscale, NordVPN.

# 1. NetworkManager VPN or WireGuard connection (prints the connection name).
nm_vpn=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
    | awk -F: '$2 == "vpn" || $2 == "wireguard" {print $1; exit}')
if [[ -n "$nm_vpn" ]]; then
    echo "$nm_vpn"
    exit 0
fi

# 2. Tailscale (up when `tailscale status` exits 0; non-zero when stopped).
if command -v tailscale >/dev/null 2>&1; then
    if tailscale status >/dev/null 2>&1; then
        echo "tailscale"
        exit 0
    fi
fi

# 3. NordVPN (prints the server when connected).
if command -v nordvpn >/dev/null 2>&1; then
    server=$(nordvpn status 2>/dev/null | awk -F': ' '/Server:/ {print $2; exit}')
    if [[ -n "$server" ]]; then
        echo "$server"
        exit 0
    fi
fi

echo "x"
