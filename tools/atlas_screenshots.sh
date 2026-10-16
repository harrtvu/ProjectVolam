#!/usr/bin/env bash
# Regenerates docs/atlas_map.png, docs/atlas_tooltip.png, docs/atlas_passives.png
# (needs a display, e.g. xvfb-run -a -s "-screen 0 1280x720x24" tools/atlas_screenshots.sh).
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 tools/atlas_screenshots.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
T=$(mktemp -d); S="$T/accounts.json"
# a mid-progress atlas: Fire region cleared up to its Guardian, a few bonus objectives, 14 passives
python3 - "$S" <<'PY'
import hashlib, json, sys
salt = "0123456789abcdef"
done = {k: 1 for k in ["wood:1", "wood:2", "wood:3", "wood:5", "water:1", "water:2", "water:3", "earth:1", "earth:2",
                       "fire:1", "fire:2", "fire:3", "fire:5", "fire:7", "fire:10", "metal:1", "metal:2"]}
done["fire:1"] = 4
atlas = {"v": 2, "done": done, "bonus": {k: True for k in ["fire:1", "fire:2", "fire:3", "wood:1", "water:1"]},
         "passives": ["a_ring_fire", "a_fire_1", "a_fire_2", "a_fire_3", "a_fire_4", "a_fire_5", "a_ring_water", "a_water_1",
                      "a_water_3", "a_ring_metal", "a_metal_2", "a_cross_metal", "a_ring_wood", "a_wood_1"], "migrated": []}
acc = {"name": "Cartographer", "salt": salt, "hash": hashlib.sha256((salt + "s").encode()).hexdigest(), "created": "2026-10-15T12:00:00",
       "character": {"class": "fire", "level": 30, "xp": 0, "hp": 200, "gold": 5000, "zone": "meadow", "atlas": atlas}}
json.dump({"accounts": {"cartographer": acc}}, open(sys.argv[1], "w"), indent="\t")
PY
"$GODOT" --headless --path . -- --server --save-file="$S" --quit-after=60 > $T/server.log 2>&1 &
sleep 2
w() { "$GODOT" --path . --resolution 1152x648 -- --join=127.0.0.1 --name=Cartographer --password=s --bot-idle "$@"; }
w --open-atlas=map --screenshot=docs/atlas_map.png --screenshot-delay=8 --quit-after=10 > $T/c1.log 2>&1
w --open-atlas=map@water:5 --screenshot=docs/atlas_tooltip.png --screenshot-delay=8 --quit-after=10 > $T/c2.log 2>&1
w --open-atlas=tree@a_water_5 --screenshot=docs/atlas_passives.png --screenshot-delay=8 --quit-after=10 > $T/c3.log 2>&1
kill %1 2>/dev/null; wait
grep -h "screenshot\|SCRIPT ERROR\|ERROR\|atlas panel" $T/*.log
echo "logs in $T"
