#!/bin/sh
xrandr --setprovideroutputsource NVIDIA-G0 modesetting
#xrandr --output HDMI-1 --off --output DP-1-1 --primary --mode 3840x2160 --pos 0x0 --rotate normal --output eDP-1 --off --output DP-2 --off
#xrandr --output eDP-1 --off --output DP-1-1 --auto
xrandr --auto
xrandr --output DP-1-1 --auto --primary
