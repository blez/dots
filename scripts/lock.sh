#!/usr/bin/env bash
# Screen locker, run by `xss-lock --transfer-sleep-lock` (xmonad startup hook)
# on `loginctl lock-session`, before sleep and on screensaver timeout.
# Also run directly by lock-now.sh when xss-lock isn't running.
# Runs i3lock with dunst paused, so notification popups (and their message
# previews) aren't drawn over the lock screen. Notifications that arrive
# while locked are queued and pop up after unlock.
# Stays running until unlock, as xss-lock expects of its locker.

lock_args=(-i ~/wallpapers/lock.png)

# one instance at a time, so a second one can't save the first one's
# "paused" as the level to restore (i3lock and pidwait, which can outlive us,
# are kept from inheriting it)
exec {instance_fd}>"${XDG_RUNTIME_DIR:-/tmp}/lock.sh.lock"
flock -n "$instance_fd" || exit 0

# loginctl unlock-session: xss-lock sends us TERM
unlock_requested=
on_term() { unlock_requested=1; pkill -xu "$EUID" i3lock; }
trap on_term TERM INT

# restore the previous pause level however we exit (short of SIGKILL); the
# level, not just paused/unpaused, so partial do-not-disturb survives a lock
# (timeouts: a hung dunst mustn't hold up locking before sleep)
pause_level=$(timeout 1 dunstctl get-pause-level)
restore() { [ -n "$pause_level" ] && timeout 1 dunstctl set-pause-level "$pause_level"; }
trap restore EXIT
# ignore HUP: exiting on it would restore dunst with i3lock still up
trap '' HUP
timeout 1 dunstctl set-paused true

# i3lock fails if another client (a menu, a drag) holds a keyboard/pointer
# grab; keep retrying for a while rather than going to sleep unlocked
# (logind holds off sleep until the fd is closed, up to InhibitDelayMaxSec).
# i3lock forks once the screen is locked, and itself closes the inherited
# XSS_SLEEP_LOCK_FD at that point.
locked=
SECONDS=0
until [ -n "$unlock_requested" ]; do
  # an i3lock is already up (started some other way): just wait for it
  if pgrep -xu "$EUID" i3lock >/dev/null || i3lock "${lock_args[@]}" {instance_fd}>&-; then
    locked=1
    break
  fi
  (( SECONDS >= 10 )) && break
  sleep 0.5
done

# close our copy of the fd too, so logind lets the system sleep
[[ -n $XSS_SLEEP_LOCK_FD ]] && exec {XSS_SLEEP_LOCK_FD}<&-

if [ -z "$locked" ]; then
  [ -n "$unlock_requested" ] && exit 0
  # queued while paused, shows once restore runs on exit
  notify-send -u critical "Screen lock failed" "i3lock could not grab the keyboard"
  exit 1
fi

# wait for unlock; in the background so the TERM trap can interrupt the wait
pidwait -xu "$EUID" i3lock {instance_fd}>&- &
wait $! || wait $!
