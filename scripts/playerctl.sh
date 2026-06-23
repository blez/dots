#!/usr/bin/env bash
# Control a media player, prompting with rofi when more than one distinct
# stream is active. Works with mpris-tabs (~/blez/mpris-tabs), which exposes
# each browser tab as its own MPRIS player (mpris_tabs.tabN).
#
# Usage: playerctl.sh [play|next|prev]   (default: play)
set -euo pipefail

cmd=${1:-play}

mapfile -t all < <(playerctl -l 2>/dev/null || true)

# Dedupe by track title so a single stream surfaced by two interfaces (e.g. a
# browser's built-in MPRIS plus mpris-tabs) is not listed twice. mpris_tabs.*
# entries are considered first so they win ties.
ordered=()
for p in "${all[@]}"; do [[ $p == mpris_tabs* ]] && ordered+=("$p"); done
for p in "${all[@]}"; do [[ $p == mpris_tabs* ]] || ordered+=("$p"); done

declare -A seen
players=()
for p in "${ordered[@]}"; do
    key=$(playerctl -p "$p" metadata --format '{{title}}' 2>/dev/null || true)
    [ -n "$key" ] || key="$p"
    [ -n "${seen[$key]:-}" ] && continue
    seen[$key]=1
    players+=("$p")
done

if [ "${#players[@]}" -eq 0 ]; then
    notify-send -a "Music" "No active player"
    exit 0
fi

# Fetch each status once; reuse for sorting and labels.
declare -A status_of
for p in "${players[@]}"; do
    status_of[$p]=$(playerctl -p "$p" status 2>/dev/null || echo "?")
done

# Sort: Playing first, then Paused, then anything else (stable within a group).
mapfile -t players < <(
    for p in "${players[@]}"; do
        case "${status_of[$p]}" in
            Playing) rank=0 ;;
            Paused)  rank=1 ;;
            *)       rank=2 ;;
        esac
        printf '%d\t%s\n' "$rank" "$p"
    done | sort -n -s -k1,1 | cut -f2
)

if [ "${#players[@]}" -eq 1 ]; then
    # Only one stream: no ambiguity, act on it directly.
    player=${players[0]}
else
    # Several streams: let the user pick which to control. Labels omit the
    # mpris_tabs.* player id and show "[status] artist - title" instead.
    declare -A by_label
    menu=""
    for p in "${players[@]}"; do
        track=$(playerctl -p "$p" metadata --format "{{artist}} - {{title}}" 2>/dev/null || true)
        track=${track# - }  # drop the leading "- " when a track has no artist
        label="[${status_of[$p]}]  $track"
        by_label["$label"]=$p
        menu+="$label"$'\n'
    done
    chosen=$(printf '%s' "$menu" | rofi -dmenu -i -p "player" || true)
    [ -n "$chosen" ] || exit 0
    player=${by_label["$chosen"]}
fi

case "$cmd" in
play) playerctl -p "$player" play-pause ;;
next) playerctl -p "$player" next; sleep 1 ;;
prev) playerctl -p "$player" previous; sleep 1 ;;
esac

info=$(playerctl -p "$player" metadata --format "{{ artist }} - {{ title }} ({{status}})" 2>/dev/null || true)
notify-send -a "Music" "${info# - }"
