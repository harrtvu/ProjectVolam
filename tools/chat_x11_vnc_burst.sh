#!/bin/bash
# one real window (Xvfb + xfwm4 + x11vnc), VNC-typed back-to-back chat lines at a low frame rate
G=/workspace/tools/Godot_v4.2.1-stable_linux.x86_64; P=${PORT:-8850}; O=${OUTROOT:-/workspace/scratch/chat}/${TAG:-r3}; mkdir -p $O; rm -f $O/*
R=${REPO:-/workspace/project-volam}; cd $R
$G --headless --path . -- --server --port=$P --save-file=$O/acc.json --quit-after=50 > $O/server.log 2>&1 &
export DISPLAY=:${DNUM:-92}; VP=${VP:-5992}
Xvfb $DISPLAY -screen 0 1600x1000x24 >/dev/null 2>&1 & XP=$!
sleep 1; x11vnc -display $DISPLAY -localhost -nopw -shared -forever -noxdamage -skip_lockkeys -rfbport $VP -quiet >/dev/null 2>&1 & sleep 1
xfwm4 --compositor=off --display=$DISPLAY >/dev/null 2>&1 & sleep 2
VOLAM_KEYLOG=1 $G --path . ${GX:-} -- --join=127.0.0.1 --port=$P --name=Typer --password=t --class=fire --quit-after=40 > $O/client.log 2>&1 &
sleep 14
W=$(xdotool search --name "Volam" | head -1); eval $(xdotool getwindowgeometry --shell $W)
xdotool mousemove $((X+300)) $((Y+250)) click 1; sleep 1
python3 "$(dirname "$0")/vnctype.py" $VP ${KD:-0} key:Return text:hello key:Return key:Return "text:/accept" key:Return key:Return "text:/invite Bravo" key:Return key:Return text:bye key:Return
sleep 4
grep -E "\[party\]|\[chat\] \[" $O/server.log | cut -c1-150
grep -E "Typer\(" $O/client.log | grep -o "Typer([^@]*@([0-9, ]*)" | uniq | head -3
grep -cE "character sheet|opened|toggle" $O/client.log
pkill -f "x11vnc -display $DISPLAY"; pkill -f "xfwm4 --compositor=off --display=$DISPLAY"; kill $XP 2>/dev/null; wait 2>/dev/null
