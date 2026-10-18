#!/usr/bin/env bash
# Regenerates docs/hideout_decorated.png, docs/hideout_decoration_mode.png, docs/hideout_theme.png
# (needs a display, e.g. xvfb-run -a -s "-screen 0 1280x720x24" tools/hideout_screenshots.sh).
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 tools/hideout_screenshots.sh
set -u
GODOT="${GODOT:-godot}"
PORT="${PORT:-7781}"
cd "$(dirname "$0")/.."
T=$(mktemp -d); S="$T/accounts.json"
mk() {  # theme -> a decorated hideout save (logged out inside the hideout)
python3 - "$S" "$1" <<'PY'
import hashlib, json, sys
salt = "0123456789abcdef"
decor = []
def put(i, x, y, rot=0, flip=False): decor.append({"id": i, "x": x, "y": y, "rot": rot, "flip": flip})
for x in range(18, 46, 3): put("pine" if x % 2 else "oak", x, 12)
for y in range(14, 28, 3): put("bamboo", 18, y); put("snow_pine", 45, y)
for x in (27, 29, 35, 37): put("lantern", x, 18)
put("statue", 32, 17); put("shrine", 30, 15); put("shrine", 34, 15, flip=True)
for x in range(28, 37): put("rug", x, 21)
for (x, y) in ((36, 25), (37, 25), (36, 26), (37, 26)): put("pond", x, y)
for x in (26, 38): put("pillar", x, 23); put("banner", x, 14)
for (x, y) in ((22, 27), (25, 27), (40, 27), (43, 27), (24, 22), (42, 22)): put("flowers", x, y)
put("mushroom", 27, 26); put("barrel", 43, 18); put("barrel", 43, 19); put("stump", 22, 17); put("snowman", 41, 25); put("rock", 26, 27)
owned = {}
for d in decor: owned[d["id"]] = owned.get(d["id"], 0) + 1
owned["pine"] += 3; owned["lantern"] += 1
ho = {"theme": sys.argv[2], "unlocked": ["meadow", "wood", "fire", "earth", "metal", "water"], "owned": owned, "decor": decor,
      "stations": {"map_device": [24, 15], "merchant": [21, 20], "vendor": [21, 24], "blacksmith": [40, 15]}}
acc = {"name": "Harry", "salt": salt, "hash": hashlib.sha256((salt + "s").encode()).hexdigest(), "created": "2026-10-15T12:00:00",
       "character": {"class": "metal", "level": 20, "xp": 0, "hp": 200, "gold": 25000, "zone": "hideout", "pos": [32 * 32 + 16, 24 * 32 + 16], "hideout": ho}}
json.dump({"accounts": {"harry": acc}}, open(sys.argv[1], "w"), indent="\t")
PY
}
shot() {  # theme out.png [extra client options]
  mk "$1"
  "$GODOT" --headless --path . -- --server --port=$PORT --save-file="$S" --quit-after=16 > $T/server_$1.log 2>&1 &
  sleep 2
  "$GODOT" --path . --resolution 1152x648 -- --join=127.0.0.1 --port=$PORT --name=Harry --password=s --bot-idle --screenshot="$2" --screenshot-delay=9 --quit-after=11 "${@:3}" > $T/client_$1.log 2>&1
  wait
}
shot meadow docs/hideout_decorated.png
shot wood docs/hideout_decoration_mode.png --hideout-shot=mode
shot fire docs/hideout_theme.png
grep -h "screenshot\|SCRIPT ERROR\|ERROR\|restoring" $T/*.log
