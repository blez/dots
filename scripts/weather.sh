#!/usr/bin/env bash
# Current weather for xmobar, e.g. "<icon> 17°C".
# The location comes from your public IP: wttr.in does the lookup. Behind a
# VPN, that means the VPN exit's location.
#
# xmobar runs this every minute, but it only fetches when the cached reading
# is older than 15 minutes, so a boot without network fills in as soon as the
# network comes up. If a fetch fails, the last reading is shown for up to
# 3 hours, then nothing. The icon is worked out on every run, so an old
# reading still switches between day and night icons.
set -uo pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}/xmobar-weather"
refresh=$((15 * 60))
stale=$((3 * 60 * 60))

age() { echo $(($(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0))); }

# Fetch and cache one reading as tab-separated fields:
#   weather code, temperature (°C), sunrise, sunset, location time zone.
fetch() {
    local json code temp rise set tz tmp
    json=$(curl -fsS --max-time 10 'https://wttr.in/?format=j1' 2>/dev/null) || return 1
    IFS=$'\t' read -r code temp rise set < <(jq -r '[
        (.current_condition[0].weatherCode // ""),
        (.current_condition[0].temp_C // ""),
        (.weather[0].astronomy[0].sunrise // "" | gsub(" "; "")),
        (.weather[0].astronomy[0].sunset  // "" | gsub(" "; ""))
    ] | @tsv' <<<"$json" 2>/dev/null) || return 1
    # Only a numeric code and temperature count as a reading.
    [[ "$code" =~ ^[0-9]+$ && "$temp" =~ ^-?[0-9]+$ ]] || return 1
    # Sunrise/sunset are in the location's local time; keep its time zone so
    # day/night doesn't depend on the system time zone being right.
    tz=$(curl -fsS --max-time 10 'https://wttr.in/?format=%Z' 2>/dev/null) || tz=""
    [[ "$tz" =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$ ]] || tz=""

    mkdir -p "$(dirname "$cache")" || return 1
    tmp=$(mktemp "$cache.XXXXXX") || return 1
    printf '%s\t%s\t%s\t%s\t%s\n' "$code" "$temp" "$rise" "$set" "$tz" >"$tmp" &&
        mv "$tmp" "$cache" || { rm -f "$tmp"; return 1; }
}

# Nerd Font weather glyph for a wttr.in (WorldWeatherOnline) condition code.
icon() {
    local code=$1 night=$2
    case "$code" in
        113) [ "$night" = 1 ] && printf '' || printf '' ;;  # clear
        116) [ "$night" = 1 ] && printf '' || printf '' ;;  # partly cloudy
        119 | 122) printf '' ;;                                     # cloudy
        143 | 248 | 260) printf '' ;;                               # fog
        176 | 263 | 266 | 293 | 296 | 353) printf '' ;;             # light rain
        299 | 302 | 305 | 308 | 356 | 359) printf '' ;;             # rain
        179 | 227 | 230 | 323 | 326 | 329 | 332 | 335 | 338 | 368 | 371)
            printf '' ;;                                            # snow
        182 | 185 | 281 | 284 | 311 | 314 | 317 | 320 | 350 | 362 | 365 | 374 | 377)
            printf '' ;;                                            # sleet
        200 | 386 | 389 | 392 | 395) printf '' ;;                   # thunder
        *) printf '' ;;
    esac
}

render() {
    local code temp rise set tz now r s night=0
    IFS=$'\t' read -r code temp rise set tz <"$cache" || return 1
    [[ "$code" =~ ^[0-9]+$ && "$temp" =~ ^-?[0-9]+$ ]] || return 1
    # Compare in the location's time zone (system zone if unknown).
    if [ -n "$tz" ]; then now=$(TZ="$tz" date +%H%M); else now=$(date +%H%M); fi
    r=$(date -d "$rise" +%H%M 2>/dev/null || echo 0600)
    s=$(date -d "$set" +%H%M 2>/dev/null || echo 1800)
    if [ "$now" -lt "$r" ] || [ "$now" -ge "$s" ]; then night=1; fi
    printf '%s %s°C\n' "$(icon "$code" "$night")" "$temp"
}

# Fetch when there's no usable reading (missing, unreadable, e.g. left by an
# older version of this script) or when it's due for a refresh.
if ! render >/dev/null 2>&1 || [ "$(age)" -ge "$refresh" ]; then
    fetch || true
fi
if [ -s "$cache" ] && [ "$(age)" -lt "$stale" ]; then
    render || true
fi
