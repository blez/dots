#!/usr/bin/env bash
# Current weather for xmobar, e.g. "<icon> 17°C Lviv".
# The location comes from your public IP: wttr.in does the lookup. Behind a
# VPN, that means the VPN exit's location. When wttr.in is down, Open-Meteo is
# used instead, with the location looked up from your IP via ipinfo.io.
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

# Each source prints one reading as fields separated by $sep:
#   weather code, temperature (°C), sunrise, sunset, location time zone, place.
# The code is a wttr.in (WorldWeatherOnline) code; other sources map to it.
# Sunrise/sunset are in the location's local time; the time zone is kept so
# day/night doesn't depend on the system time zone being right.
# The separator isn't a tab: read merges runs of tabs, so an empty field
# would shift the ones after it.
sep=$'\x1f'

# Where the public IP is, from ipinfo.io: sets ip_city and ip_loc ("lat,lon").
ip_city="" ip_loc=""
locate() {
    local json
    json=$(curl -fsS --max-time 10 'https://ipinfo.io/json' 2>/dev/null) || return 1
    IFS=$sep read -r ip_city ip_loc < <(jq -r --arg s "$sep" \
        '[(.city // ""), (.loc // "")] | join($s)' <<<"$json" 2>/dev/null)
    [[ "$ip_loc" =~ ^-?[0-9.]+,-?[0-9.]+$ ]] || ip_loc=""
}

from_wttr() {
    local json tz
    json=$(curl -fsS --max-time 10 'https://wttr.in/?format=j1' 2>/dev/null) || return 1
    tz=$(curl -fsS --max-time 10 'https://wttr.in/?format=%Z' 2>/dev/null) || tz=""
    jq -r --arg tz "$tz" --arg s "$sep" '[
        (.current_condition[0].weatherCode // ""),
        (.current_condition[0].temp_C // ""),
        (.weather[0].astronomy[0].sunrise // "" | gsub(" "; "")),
        (.weather[0].astronomy[0].sunset  // "" | gsub(" "; "")),
        $tz,
        (.nearest_area[0].areaName[0].value // "")
    ] | map(tostring) | join($s)' <<<"$json" 2>/dev/null
}

# Open-Meteo reports WMO weather codes; map them to the nearest wttr.in code.
wmo_to_wwo() {
    case "$1" in
        0) echo 113 ;;                         # clear
        1 | 2) echo 116 ;;                     # mainly clear, partly cloudy
        3) echo 119 ;;                         # overcast
        45 | 48) echo 248 ;;                   # fog
        51 | 53 | 55) echo 266 ;;              # drizzle
        61 | 80) echo 296 ;;                   # light rain / showers
        63 | 65 | 81 | 82) echo 308 ;;         # rain / heavy showers
        56 | 57 | 66 | 67) echo 311 ;;         # freezing drizzle/rain
        71 | 73 | 75 | 77 | 85 | 86) echo 338 ;; # snow
        95 | 96 | 99) echo 389 ;;              # thunderstorm
        *) return 1 ;;
    esac
}

from_openmeteo() {
    local loc=$ip_loc json code temp rise set tz
    [ -n "$loc" ] || return 1
    json=$(curl -fsS --max-time 10 "https://api.open-meteo.com/v1/forecast?latitude=${loc%,*}&longitude=${loc#*,}&current=temperature_2m,weather_code&daily=sunrise,sunset&timezone=auto&forecast_days=1" 2>/dev/null) || return 1
    IFS=$sep read -r code temp rise set tz < <(jq -r --arg s "$sep" '[
        (.current.weather_code // ""),
        (.current.temperature_2m // "" | if type == "number" then round else . end),
        (.daily.sunrise[0] // "" | sub("^.*T"; "")),
        (.daily.sunset[0]  // "" | sub("^.*T"; "")),
        (.timezone // "")
    ] | map(tostring) | join($s)' <<<"$json" 2>/dev/null) || return 1
    code=$(wmo_to_wwo "$code") || return 1
    [[ "$temp" =~ ^-?[0-9]+$ ]] && temp=$((temp))  # no "-0°C"
    printf "%s$sep%s$sep%s$sep%s$sep%s$sep%s\n" "$code" "$temp" "$rise" "$set" "$tz" "$ip_city"
}

# Fetch a reading, trying wttr.in first, and cache it.
fetch() {
    local src code temp rise set tz place tmp
    locate || true
    for src in from_wttr from_openmeteo; do
        IFS=$sep read -r code temp rise set tz place < <("$src") || continue
        # Only a numeric code and temperature count as a reading.
        [[ "$code" =~ ^[0-9]+$ && "$temp" =~ ^-?[0-9]+$ ]] && break
        code=""
    done
    [ -n "$code" ] || return 1
    [[ "$tz" =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$ ]] || tz=""
    # Prefer ipinfo's city: wttr.in's area is often a nearby village.
    place=${ip_city:-$place}
    place=${place//[<>%{\}]/}  # nothing xmobar would read as markup

    mkdir -p "$(dirname "$cache")" || return 1
    tmp=$(mktemp "$cache.XXXXXX") || return 1
    printf "%s$sep%s$sep%s$sep%s$sep%s$sep%s\n" "$code" "$temp" "$rise" "$set" "$tz" "$place" >"$tmp" &&
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
    local code temp rise set tz place now r s night=0
    IFS=$sep read -r code temp rise set tz place <"$cache" || return 1
    [[ "$code" =~ ^[0-9]+$ && "$temp" =~ ^-?[0-9]+$ ]] || return 1
    # Compare in the location's time zone (system zone if unknown).
    if [ -n "$tz" ]; then now=$(TZ="$tz" date +%H%M); else now=$(date +%H%M); fi
    r=$(date -d "$rise" +%H%M 2>/dev/null || echo 0600)
    s=$(date -d "$set" +%H%M 2>/dev/null || echo 1800)
    if [ "$now" -lt "$r" ] || [ "$now" -ge "$s" ]; then night=1; fi
    printf '%s %s°C%s\n' "$(icon "$code" "$night")" "$temp" "${place:+ $place}"
}

# Fetch when there's no usable reading (missing, unreadable, e.g. left by an
# older version of this script) or when it's due for a refresh.
if ! render >/dev/null 2>&1 || [ "$(age)" -ge "$refresh" ]; then
    fetch || true
fi
if [ -s "$cache" ] && [ "$(age)" -lt "$stale" ]; then
    render || true
fi
