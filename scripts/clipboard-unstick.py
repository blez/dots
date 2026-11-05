#!/usr/bin/env python3
"""Unfreeze Slack and Chrome when pasting hangs them (Chromium on X11).

Chromium's browser process sometimes asks the clipboard owner for its formats
(CLIPBOARD -> TARGETS) and never gets the SelectionNotify reply. It waits for
it forever, so every later paste queues behind it and the page freezes
("Crashing because hung" in the journal; reloading doesn't help).

This sends the reply itself: a SelectionNotify with property None, i.e.
"conversion refused", for TARGETS only. The app takes it as an empty format
list and moves on to the requests queued behind it, which then get real
replies. (Refusing other targets too would also fail those queued pastes.)
Replies that match no pending request are ignored, so when nothing is stuck
the only effect is that a paste in flight at that very moment comes back empty.
If a freeze isn't cleared and the clipboard-trace logger is running (not part
of the dotfiles), ~/.local/share/clipboard-trace/trace.log shows which target
it's stuck on.

Chromium's requestor window is the first resource id of its X connection, so
the reply goes to the base id of every connection that owns a window of one
of APPS. Bound to mod+shift+v in ~/.xmonad/xmonad.hs.
"""

import subprocess
import traceback

APPS = ("slack", "chrome", "chromium")  # substrings of the WM_CLASS instance or class
SELECTIONS = ("CLIPBOARD", "PRIMARY")


def notify(body, urgency="normal"):
    # Best effort: a missing notify-send must not mask the error being reported.
    try:
        subprocess.run(
            ["notify-send", "-a", "clipboard-unstick", "-u", urgency, "-t", "3000", "clipboard-unstick", body],
            check=False,
        )
    except OSError:
        pass


def app_windows(d, error):
    """{base window: app name} for the X connections that own an APPS window."""
    mask = d.display.info.resource_id_mask
    bases = {}
    for win in d.screen().root.query_tree().children:
        try:
            wm_class = win.get_wm_class() or ()
        except error.XError:
            continue
        names = [c.lower() for c in wm_class]
        app = next((a for a in APPS if any(a in n for n in names)), None)
        if app:
            bases.setdefault(win.id & ~mask, app)
    # Only Chromium's own connection creates a window at its base id (GTK's doesn't).
    found = {}
    for base, app in sorted(bases.items()):
        win = d.create_resource_object("window", base)
        try:
            win.get_attributes()
        except error.BadWindow:
            continue
        found[win] = app
    return found


def main():
    from Xlib import X, display, error
    from Xlib.protocol import event

    d = display.Display()
    windows = app_windows(d, error)
    if not windows:
        notify("no Slack or Chrome window found")
        return
    targets = d.intern_atom("TARGETS")
    selections = [d.intern_atom(s) for s in SELECTIONS]
    for win in windows:
        for sel in selections:
            ev = event.SelectionNotify(
                time=X.CurrentTime, requestor=win.id, selection=sel, target=targets, property=X.NONE
            )
            win.send_event(ev, event_mask=0, propagate=False)
    d.sync()
    notify(
        "sent clipboard replies to " + ", ".join(sorted(set(windows.values())))
        + ". Still frozen? It's stuck on another format: check the clipboard-trace log."
    )


if __name__ == "__main__":
    # Spawned from xmonad with no visible stderr: report failures as a notification.
    try:
        main()
    except Exception:
        notify("failed: " + traceback.format_exc(limit=1).strip().splitlines()[-1], urgency="critical")
        raise
