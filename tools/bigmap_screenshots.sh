#!/usr/bin/env bash
# Regenerates docs/bigmap_overview.png (full zone map, N), docs/bigmap_groups.png (a forest monster camp in game)
# and docs/bigmap_minimap.png (an elite pack in the crypt + the minimap).
# Needs a display, e.g. xvfb-run -a -s "-screen 0 1280x720x24" tools/bigmap_screenshots.sh
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 tools/bigmap_screenshots.sh
set -u
GODOT="${GODOT:-godot}"
PORT="${PORT:-7782}"
cd "$(dirname "$0")/.."
T=$(mktemp -d)
"$GODOT" --headless --path . -- --bigmap-selftest > $T/selftest.log 2>&1
first() { grep -E "BIGMAP SELFTEST $1 +$2 at" $T/selftest.log | sed -E "s/.*$2 at ([0-9]+,[0-9]+).*/\1/"; }
CAMP=$(first forest camps); ELITE=$(grep -E "BIGMAP SELFTEST crypt +camps" $T/selftest.log | sed -E 's/.*elites at ([0-9]+,[0-9]+).*/\1/')
shift_cell() { echo "$1" | awk -F, -v dx=$2 -v dy=$3 '{print $1+dx "," $2+dy}'; }
shot() {  # name out.png delay [client options]
  "$GODOT" --headless --path . -- --server --port=$PORT --save-file="$T/$1.json" --debug-start-level=20 --allow-warp --quit-after=20 > $T/server_$1.log 2>&1 &
  sleep 2
  "$GODOT" --path . --resolution 1152x648 -- --join=127.0.0.1 --port=$PORT --name=Harry --password=s --class=metal --bot-idle --screenshot="$2" --screenshot-delay=$3 --quit-after=$(( $3 + 3 )) "${@:4}" > $T/client_$1.log 2>&1
  wait
}
shot overview docs/bigmap_overview.png 6 --warp=meadow --warp-cell=166,64 --open-zone-map
shot groups docs/bigmap_groups.png 4 --warp=forest --warp-cell=$(shift_cell $CAMP 0 3)
shot minimap docs/bigmap_minimap.png 5 --warp=crypt --warp-cell=$(shift_cell $ELITE 0 4)
echo "camp $CAMP elite $ELITE; logs in $T"
