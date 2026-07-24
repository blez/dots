#!/bin/bash
set -euo pipefail

# Fixes the case where Galaxy Buds are connected but no PipeWire audio sink
# is created, so audio keeps playing from the laptop speakers.
# Reconnects the device (BlueZ re-offers A2DP), then makes it the default sink.
#
# Usage: buds-audio-fix.sh [MAC]   (defaults to the Buds3 Pro)

mac="${1:-A0:B0:BD:F3:BA:41}"
sink="bluez_output.${mac//:/_}.1"

echo "Reconnecting $mac ..."
bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
sleep 3
bluetoothctl connect "$mac" >/dev/null

# Wait for the PipeWire sink to appear (up to ~10s)
for _ in $(seq 1 10); do
    if pactl list short sinks | grep -q "$sink"; then
        break
    fi
    sleep 1
done

if ! pactl list short sinks | grep -q "$sink"; then
    echo "Sink $sink did not appear — is a bud out of the case?" >&2
    exit 1
fi

pactl set-default-sink "$sink"

# Move any currently-playing streams onto the buds
for id in $(pactl list short sink-inputs | awk '{print $1}'); do
    pactl move-sink-input "$id" "$sink" 2>/dev/null || true
done

echo "Default output is now $sink (profile: $(pactl list cards | awk '/bluez_card/{f=1} f&&/Active Profile/{print $3; exit}'))"
