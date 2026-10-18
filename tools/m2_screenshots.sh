#!/usr/bin/env bash
# Regenerates the Milestone 2 screenshots in docs/m2/ with the real renderer:
#   play_solo_menu.png, vendor_ui.png, tutorial.png, party_dungeon.png
# Needs a display, e.g. xvfb-run -a -s "-screen 0 1280x720x24" tools/m2_screenshots.sh
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 PORT=7960 tools/m2_screenshots.sh
set -u
GODOT="${GODOT:-godot}"
PORT="${PORT:-7960}"
cd "$(dirname "$0")/.."
T=$(mktemp -d)
R="--resolution 1152x648"
srv() {  # name quit-after [extra server options]
  "$GODOT" --headless --path . -- --server --port=$PORT --save-file="$T/$1.json" --allow-warp --quit-after=$2 "${@:3}" > $T/server_$1.log 2>&1 &
  sleep 2
}
# 1. main menu with the Play Solo button + slot picker (no server needed)
"$GODOT" --path . $R -- --screenshot=docs/m2/play_solo_menu.png --screenshot-delay=2 --quit-after=5 > $T/menu.log 2>&1
# 2. vendor panel, standing next to the vendor in Sunny Meadow
srv vendor 24 --debug-start-level=8 --debug-gear
"$GODOT" --path . $R -- --join=127.0.0.1 --port=$PORT --name=Harry --password=s --class=metal --bot-idle --warp=meadow --warp-cell=156,68 --open-vendor --screenshot=docs/m2/vendor_ui.png --screenshot-delay=10 --quit-after=14 > $T/vendor.log 2>&1
wait
# 3. tutorial overlay for a brand-new character
srv tutorial 18
"$GODOT" --path . $R -- --join=127.0.0.1 --port=$PORT --name=Newbie --password=s --class=fire --bot-idle --show-tutorial --screenshot=docs/m2/tutorial.png --screenshot-delay=7 --quit-after=11 > $T/tutorial.log 2>&1
wait
# 4. two-player party inside the same dungeon instance (screenshot from the member's view)
srv party 90 --debug-start-level=20 --debug-gear
"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$PORT --name=Leader --password=p --bot --bot-no-gear --class=fire --bot-dungeon=full --bot-dungeon-theme=fire --bot-party=invite:Member --quit-after=85 > $T/leader.log 2>&1 &
"$GODOT" --path . $R -- --join=127.0.0.1 --port=$PORT --name=Member --password=p --bot --bot-no-gear --class=water --bot-dungeon=party --bot-party=accept --screenshot=docs/m2/party_dungeon.png --screenshot-when=dungeon --screenshot-delay=5 --quit-after=85 > $T/member.log 2>&1
wait
grep -h "screenshot saved" $T/*.log
echo "logs in $T"
