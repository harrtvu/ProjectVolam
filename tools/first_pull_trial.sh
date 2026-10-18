#!/usr/bin/env bash
# First pull of a FRESH Lv6 character (no gear, 5+5 potions, debug Lv6) in Forest Den T1:
# solo, and as a party of two (leader opens, member follows). Each player's first 20 s inside
# are summarised by the server: "FIRST PULL <name> ... survived|DIED after ... hp min ...".
# CLI_EXTRA="--bot-no-potions" = no potions. SRV_EXTRA="--no-xp" keeps everyone at Lv6 (level-ups refill HP and hide the damage).
# REAL_KIT=1 = the trial characters get the real new-player kit (3 Health Potions, 0 gold) instead of the 5+5 debug kit.
# Usage: GODOT=... tools/first_pull_trial.sh [class=fire] [outdir=test-logs/fp] [port=8680] [theme=wood]
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
CLS="${1:-fire}"; OUT="${2:-test-logs/fp}"; PORT="${3:-8680}"; THEME="${4:-wood}"
mkdir -p "$OUT"; rm -f "$OUT"/*.log "$OUT"/*.json
run() { "$GODOT" --headless --path . -- "$@"; }
case "$OUT" in /*) S="$OUT/save.json" ;; *) S="$(pwd)/$OUT/save.json" ;; esac
run --server --port=$PORT --save-file="$S" --debug-level-for=Solo:6,Lead:6,Mate:6 ${REAL_KIT:+--debug-real-kit} ${SRV_EXTRA:-} --quit-after=75 > $OUT/server.log 2>&1 &
sleep 2
c() { n=$1; shift; run --join=127.0.0.1 --port=$PORT --name=$n --password=p --class=$CLS --bot --bot-no-gear ${CLI_EXTRA:-} "$@" --quit-after=70 > $OUT/$n.log 2>&1 & }
c Solo --bot-dungeon=first --bot-dungeon-theme=$THEME --bot-dungeon-tier=1
c Lead --bot-dungeon=first --bot-dungeon-theme=$THEME --bot-dungeon-tier=1 --bot-party=invite:Mate
c Mate --bot-dungeon=party --bot-party=accept
wait
grep -hE "FIRST PULL|FIRST PACK|entrance safe area|populated" $OUT/server.log
