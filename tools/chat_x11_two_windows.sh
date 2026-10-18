#!/bin/bash
# two real windows on one Xvfb+xfwm4 display (like PlayTester's desktop); click a window, Enter, type
G=/workspace/tools/Godot_v4.2.1-stable_linux.x86_64; P=${PORT:-8810}; O=${OUTROOT:-/workspace/scratch/chat}/${TAG:-two}; mkdir -p $O; rm -f $O/*
R=${REPO:-/workspace/project-volam}; cd $R
$G --headless --path . -- --server --port=$P --save-file=$O/acc.json --quit-after=75 > $O/server.log 2>&1 &
export DISPLAY=:${DNUM:-85}
Xvfb $DISPLAY -screen 0 1920x1200x24 >/dev/null 2>&1 & XP=$!
sleep 1; x11vnc -display $DISPLAY -localhost -nopw -shared -forever -noxdamage -skip_lockkeys -rfbport ${VP:-5985} -quiet >/dev/null 2>&1 & sleep 1; xfwm4 --compositor=off --display=$DISPLAY >/dev/null 2>&1 & sleep 2
$G --path . ${GX:-} -- --join=127.0.0.1 --port=$P --name=Alpha --password=a --class=water --quit-after=65 > $O/alpha.log 2>&1 &
sleep 4
$G --path . ${GX:-} -- --join=127.0.0.1 --port=$P --name=Bravo --password=b --class=fire --quit-after=62 > $O/bravo.log 2>&1 &
sleep 14
WA=$(xdotool search --name "Volam" | head -1); WB=$(xdotool search --name "Volam" | tail -1)
xdotool windowmove $WA 0 0; xdotool windowmove $WB 960 0; sleep 1
say() { # window text
  local w=$1; shift
  eval $(xdotool getwindowgeometry --shell $w); xdotool mousemove $((X+300)) $((Y+250)) click 1; sleep ${CLICKGAP:-0.6}
  if [ -n "${VNC:-}" ]; then python3 "$(dirname "$0")/vnctype.py" ${VP:-5985} ${KD:-0} key:Return "text:$*" key:Return
  else xdotool key --delay ${KD:-20} Return; xdotool type --delay ${KD:-20} "$*"; xdotool key Return; fi; sleep 2
}
say $WA "/invite Bravo"
say $WB "/accept"
say $WA "/p hello team"
say $WB "abc from bravo"
say $WA "/leave"
sleep 2
grep -E "\[party\]|\[chat\] \[" $O/server.log | cut -c1-150
pkill -f "x11vnc -display $DISPLAY"; pkill -f "xfwm4 --compositor=off --display=$DISPLAY"; kill $XP 2>/dev/null; wait 2>/dev/null
