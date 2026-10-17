#!/usr/bin/env bash
# ART STYLE TEST (branch art-test): before/after captures of the same spots + a combat frame sequence/clip.
# Writes docs/art_test/{before,after}_{town,wilds,group,boss}.png, docs/art_test/combat/combat_NN.png, docs/art_test/combat.mp4
# Needs a display: xvfb-run -a -s "-screen 0 1280x720x24" tools/art_test_screenshots.sh
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 tools/art_test_screenshots.sh [views|combat|all]
set -u
GODOT="${GODOT:-godot}"
PORT="${PORT:-7784}"
WHAT="${1:-all}"
cd "$(dirname "$0")/.."
OUT=docs/art_test; mkdir -p $OUT/combat
T=$(mktemp -d)
"$GODOT" --headless --path . -- --bigmap-selftest > $T/selftest.log 2>&1
CAMP=$(grep -E "BIGMAP SELFTEST forest +camps at" $T/selftest.log | sed -E "s/.*camps at ([0-9]+,[0-9]+).*/\1/")
shift_cell() { echo "$1" | awk -F, -v dx=$2 -v dy=$3 '{print $1+dx "," $2+dy}'; }
shot() {  # name out.png delay [client options]
  "$GODOT" --headless --path . -- --server --port=$PORT --save-file="$T/$1.json" --debug-start-level=20 --allow-warp --quit-after=$(( $3 + 14 )) > $T/server_$1.log 2>&1 &
  sleep 2
  "$GODOT" --path . --resolution 1152x648 -- --join=127.0.0.1 --port=$PORT --name=Harry --password=s --class=metal --bot-idle --screenshot="$2" --screenshot-delay=$3 --quit-after=$(( $3 + 3 )) "${@:4}" > $T/client_$1.log 2>&1
  wait
}
if [ "$WHAT" != combat ]; then
  for mode in before after; do
    A=""; [ $mode = after ] && A="--art-test"
    case " ${VIEWS:-town wilds group boss} " in *" town "*) shot town_$mode $OUT/${mode}_town.png 5 --warp=meadow --warp-cell=166,66 $A;; esac
    case " ${VIEWS:-town wilds group boss} " in *" wilds "*) shot wilds_$mode $OUT/${mode}_wilds.png 5 --warp=forest --warp-cell=12,22 $A;; esac
    case " ${VIEWS:-town wilds group boss} " in *" group "*) shot group_$mode $OUT/${mode}_group.png 5 --warp=forest --warp-cell=$(shift_cell $CAMP 0 3) $A;; esac
    # boss lair: stand 6 tiles from the Broodmother and shoot after 3 s, before it closes in
    case " ${VIEWS:-town wilds group boss} " in *" boss "*) shot boss_$mode $OUT/${mode}_boss.png 3 --warp=forest --warp-cell=178,113 $A;; esac
  done
fi
if [ "$WHAT" != views ]; then
  # one bot per element (headless) fighting the same camp; an idle rendered client (Harry) films it from the camp
  "$GODOT" --headless --path . -- --server --port=$PORT --save-file="$T/combat.json" --debug-start-level=${LV:-10} --allow-warp --fast-respawn --quit-after=60 > $T/server_combat.log 2>&1 &
  sleep 2
  i=-3
  for c in metal wood water fire earth; do
    i=$((i+1))
    "$GODOT" --headless --path . -- --join=127.0.0.1 --port=$PORT --name=Art$c --password=s --class=$c --bot --warp=forest --warp-cell=$(shift_cell $CAMP $i 3) --quit-after=50 > $T/bot_$c.log 2>&1 &
  done
  "$GODOT" --path . --resolution 1152x648 -- --join=127.0.0.1 --port=$PORT --name=Harry --password=s --class=metal --bot-idle --warp=forest --warp-cell=$(shift_cell $CAMP 0 2) \
    --art-test --screenshot=$OUT/combat/combat.png --screenshot-delay=${DELAY:-5} --screenshot-seq=${SEQ:-60} --screenshot-interval=${INTERVAL:-0.2} --quit-after=40 > $T/client_combat.log 2>&1
  wait
  command -v ffmpeg > /dev/null && ffmpeg -y -loglevel error -framerate 5 -i $OUT/combat/combat_%02d.png -vf "scale=1152:648:flags=neighbor,format=yuv420p" -c:v libx264 $OUT/combat.mp4
fi
echo "camp $CAMP; logs in $T"
