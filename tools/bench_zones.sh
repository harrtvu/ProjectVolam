#!/usr/bin/env bash
# Client frame-time benchmark: for each zone, a dedicated server + one rendering client standing at the
# zone entrance (debug level 20, idle) for SECS seconds; prints the client's "BENCH ..." line.
# Needs a display, e.g. xvfb-run -a -s "-screen 0 1280x720x24" tools/bench_zones.sh
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 tools/bench_zones.sh [zones...]   (SECS=8 PORT=7783; SRV_ARGS=--no-interest to compare, CELL=x,y to stand elsewhere)
set -u
GODOT="${GODOT:-godot}"
PORT="${PORT:-7783}"
SECS="${SECS:-8}"
cd "$(dirname "$0")/.."
T=$(mktemp -d)
ZONES="${*:-meadow forest crypt frost}"
for z in $ZONES; do
  "$GODOT" --headless --path . -- --server --port=$PORT --save-file="$T/a.json" --debug-start-level=20 --allow-warp ${SRV_ARGS:-} --quit-after=$((SECS + 14)) > $T/server_$z.log 2>&1 &
  sleep 2
  "$GODOT" --path . --resolution 1152x648 -- --join=127.0.0.1 --port=$PORT --name=Bench$z --password=b --class=metal --bot-idle --warp=$z ${CELL:+--warp-cell=$CELL} --bench=$SECS --quit-after=$((SECS + 10)) 2>&1 | grep "^BENCH" || echo "BENCH zone=$z FAILED (see $T)"
  wait
done
