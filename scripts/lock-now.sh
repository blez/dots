#!/usr/bin/env bash
# Lock the screen now, or with `suspend`, lock and then suspend (xmonad keys).
# Normally goes through xss-lock (`loginctl lock-session`, and its pre-sleep
# lock); runs lock.sh directly when xss-lock isn't running or that fails.

xss_lock_running() { pgrep -xu "$EUID" xss-lock >/dev/null; }

if [ "$1" != suspend ]; then
  xss_lock_running && loginctl lock-session && exit
  exec ~/scripts/lock.sh
fi

xss_lock_running && exec systemctl suspend

# Without xss-lock: hand lock.sh a pipe as the sleep-lock fd, the way xss-lock
# does. It (and i3lock) close it once the screen is locked or locking failed,
# so cat returning means it's time to check.
{ XSS_SLEEP_LOCK_FD=3 ~/scripts/lock.sh 3>&1 >/dev/null & } | timeout 20 cat

if pgrep -xu "$EUID" i3lock >/dev/null; then
  exec systemctl suspend
fi
notify-send -u critical "Not suspending" "the screen could not be locked"
exit 1
