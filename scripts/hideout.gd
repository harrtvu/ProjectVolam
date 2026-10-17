class_name Hideouts
## Path-of-Exile-style hideouts: data + pure validation (server and clients share it).
##
## A hideout is a private per-account dynamic zone ("ho<N>", see hideout_server.gd)
## built from the account's layout:
##   {"theme": id, "unlocked": [ids], "stations": {station: [x, y]},
##    "decor": [{"id": catalog id, "x", "y", "rot": 0-3, "flip": bool}], "owned": {catalog id: count}}
## Stations reuse the town station keys ("map_device", "merchant", "broker",
## "blacksmith" - the blacksmith includes the stash), so every near_*() check and
## every station feature works unchanged inside a hideout.

const BOSS_DECOR_CHANCE := 0.08   # a completed dungeon (boss down) drops a random decoration

const ROOM := Rect2i(17, 11, 30, 18)       # walkable interior (walls around it)
const DOOR := Rect2i(31, 29, 2, 1)         # exit portal in the bottom wall
const DOOR_LANE := Rect2i(29, 25, 6, 4)    # kept free in front of the door
const ARRIVE := Vector2i(32, 26)           # where you appear inside
const TOWN_NPC := Vector2i(40, 22)         # Hideout Master in Sunny Meadow
const TOWN_ARRIVE := Vector2i(176, 68)     # where the door drops you in town (next to the Hideout Master)
const MAX_DECOR := 200
const STATIONS := ["map_device", "merchant", "broker", "blacksmith"]
const STATION_NAMES := {"map_device": "Map Device", "merchant": "Ticket Merchant", "broker": "Trade Broker", "blacksmith": "Blacksmith & Stash"}
const DEFAULT_STATIONS := {"map_device": [24, 15], "merchant": [20, 19], "broker": [20, 24], "blacksmith": [40, 15]}

const THEMES := {
	"meadow": {"name": "Meadow Retreat", "element": "", "floor": ["GRASS", "GRASS", "GRASS2", "FLOWER"], "wall": "TREE", "tint": [1.0, 1.0, 1.0]},
	"wood": {"name": "Bamboo Courtyard", "element": "wood", "floor": ["F_GRASS", "F_GRASS2", "F_GRASS"], "wall": "F_PINE", "tint": [0.9, 1.05, 0.85]},
	"fire": {"name": "Ember Forge", "element": "fire", "floor": ["C_SAND", "C_FLOOR", "C_FLOOR2"], "wall": "C_WALL", "tint": [1.25, 0.8, 0.6]},
	"earth": {"name": "Stone Temple", "element": "earth", "floor": ["C_FLOOR", "C_FLOOR2", "C_RUBBLE"], "wall": "C_WALL_BANNER", "tint": [1.05, 0.95, 0.8]},
	"metal": {"name": "Golden Pavilion", "element": "metal", "floor": ["FLOOR", "FLOOR", "C_FLOOR2"], "wall": "WALL", "tint": [1.15, 1.05, 0.7]},
	"water": {"name": "Lotus Lake", "element": "water", "floor": ["S_FLOOR", "S_ICE", "S_FLOOR"], "wall": "S_WALL", "tint": [0.85, 0.95, 1.15]},
}
const THEME_ORDER := ["meadow", "wood", "fire", "earth", "metal", "water"]

## Decoration catalog: tile from the (Kenney CC0) tile atlas, gold price, drop weight.
const CATALOG := {
	"pine": {"name": "Pine Tree", "tile": "F_PINE", "price": 120},
	"oak": {"name": "Old Oak", "tile": "F_OAK", "price": 120},
	"bamboo": {"name": "Bamboo Grove", "tile": "TREE2", "price": 150},
	"snow_pine": {"name": "Snowy Pine", "tile": "S_PINE", "price": 150},
	"mushroom": {"name": "Glow Mushrooms", "tile": "F_MUSHROOM", "price": 60},
	"flowers": {"name": "Flower Bed", "tile": "FLOWER", "price": 40},
	"stump": {"name": "Tree Stump", "tile": "F_STUMP", "price": 40},
	"pillar": {"name": "Stone Pillar", "tile": "C_PILLAR", "price": 200},
	"statue": {"name": "Ancestor Statue", "tile": "C_TOMB", "price": 300},
	"shrine": {"name": "Shrine Stone", "tile": "C_GRAVE", "price": 180},
	"lantern": {"name": "Lantern Altar", "tile": "C_ALTAR", "price": 250},
	"barrel": {"name": "Barrel", "tile": "C_BARREL", "price": 50},
	"banner": {"name": "Clan Banner", "tile": "C_WALL_BANNER", "price": 220},
	"rug": {"name": "Sand Rug", "tile": "C_SAND", "price": 80},
	"pond": {"name": "Lotus Pond", "tile": "WATER", "price": 260},
	"spring": {"name": "Forest Spring", "tile": "F_WATER", "price": 260},
	"rock": {"name": "Frost Boulder", "tile": "S_ROCK", "price": 90},
	"snowman": {"name": "Snow Guardian", "tile": "S_SNOWMAN", "price": 140},
}


static func tile(name: String) -> Vector2i:
	var v := _extra(name)
	return v if v != Vector2i.ZERO else Dungeons.tile(name)


static func _extra(name: String) -> Vector2i:
	match name:
		"TREE": return Tiles.TREE
		"TREE2": return Tiles.TREE2
		"GRASS": return Tiles.GRASS
		"GRASS2": return Tiles.GRASS2
		"FLOWER": return Tiles.FLOWER
		"C_WALL_BANNER": return Tiles.C_WALL_BANNER
		"S_PINE": return Tiles.S_PINE
		"S_FLOOR": return Tiles.S_FLOOR
		"F_WATER": return Tiles.F_WATER
	return Vector2i.ZERO


static func default_layout() -> Dictionary:
	var st := {}
	for k in DEFAULT_STATIONS:
		st[k] = DEFAULT_STATIONS[k].duplicate()
	# a small starter set so a fresh hideout isn't bare
	return {"theme": "meadow", "unlocked": ["meadow"], "stations": st, "owned": {"flowers": 2, "lantern": 1},
		"decor": [{"id": "lantern", "x": 30, "y": 13, "rot": 0, "flip": false}, {"id": "flowers", "x": 34, "y": 13, "rot": 0, "flip": false}]}


static func cell_of(v: Variant) -> Vector2i:
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	if typeof(v) == TYPE_VECTOR2I:
		return v
	return Vector2i(-1, -1)


## Cells a decoration may never use: around stations (1 cell ring), the door lane.
static func blocked_reason(layout: Dictionary, cell: Vector2i, ignore_decor := -1, ignore_station := "") -> String:
	if not ROOM.has_point(cell):
		return "(%d, %d) is outside the hideout" % [cell.x, cell.y]
	if DOOR_LANE.has_point(cell):
		return "(%d, %d) would block the door" % [cell.x, cell.y]
	for s in layout.get("stations", {}):
		if s == ignore_station:
			continue
		var c := cell_of(layout["stations"][s])
		if absi(c.x - cell.x) <= 1 and absi(c.y - cell.y) <= 1:
			return "(%d, %d) is too close to the %s" % [cell.x, cell.y, STATION_NAMES.get(s, s)]
	var dec: Array = layout.get("decor", [])
	for i in dec.size():
		if i != ignore_decor and int(dec[i]["x"]) == cell.x and int(dec[i]["y"]) == cell.y:
			return "(%d, %d) already has a %s" % [cell.x, cell.y, CATALOG.get(str(dec[i]["id"]), {}).get("name", "decoration")]
	return ""


## Where a station may stand: inside, off the door lane, 2+ cells from other stations, no decoration within 1 cell.
static func station_reason(layout: Dictionary, station: String, cell: Vector2i) -> String:
	if not STATIONS.has(station):
		return "unknown station '%s'" % station
	var inner := Rect2i(ROOM.position + Vector2i.ONE, ROOM.size - Vector2i(2, 2))
	if not inner.has_point(cell):
		return "(%d, %d) is outside the hideout (or against a wall)" % [cell.x, cell.y]
	if DOOR_LANE.grow(1).has_point(cell):
		return "(%d, %d) would block the door" % [cell.x, cell.y]
	for s in layout.get("stations", {}):
		if s != station:
			var c := cell_of(layout["stations"][s])
			if absi(c.x - cell.x) <= 2 and absi(c.y - cell.y) <= 2:
				return "(%d, %d) is too close to the %s" % [cell.x, cell.y, STATION_NAMES[s]]
	for d in layout.get("decor", []):
		if absi(int(d["x"]) - cell.x) <= 1 and absi(int(d["y"]) - cell.y) <= 1:
			return "a decoration is in the way at (%d, %d)" % [int(d["x"]), int(d["y"])]
	return ""


## How many of a catalog decoration are placed.
static func placed_count(layout: Dictionary, id: String) -> int:
	var n := 0
	for d in layout.get("decor", []):
		if str(d["id"]) == id:
			n += 1
	return n


## Rebuilds a saved layout keeping only valid parts (unknown ids, out-of-bounds,
## overlapping or over-the-limit decorations are dropped; bad stations reset).
static func sanitize(v: Variant) -> Dictionary:
	var out := default_layout()
	if typeof(v) != TYPE_DICTIONARY:
		return out
	var unl: Array = ["meadow"]
	for t in v.get("unlocked", []):
		if THEMES.has(str(t)) and not unl.has(str(t)):
			unl.append(str(t))
	out["unlocked"] = unl
	out["theme"] = str(v.get("theme", "meadow")) if unl.has(str(v.get("theme", "meadow"))) else "meadow"
	if typeof(v.get("owned")) == TYPE_DICTIONARY:
		out["owned"] = {}
		for k in v["owned"]:
			if CATALOG.has(str(k)) and int(v["owned"][k]) > 0:
				out["owned"][str(k)] = mini(int(v["owned"][k]), 999)
	if typeof(v.get("stations")) == TYPE_DICTIONARY:
		var st := {}
		out["stations"] = st
		out["decor"] = []
		for s in STATIONS:
			var c := cell_of(v["stations"].get(s, DEFAULT_STATIONS[s]))
			if station_reason(out, s, c) != "":
				c = cell_of(DEFAULT_STATIONS[s])
			st[s] = [c.x, c.y]
	if typeof(v.get("decor")) == TYPE_ARRAY:
		out["decor"] = []
		for d in v["decor"]:
			if typeof(d) != TYPE_DICTIONARY or not CATALOG.has(str(d.get("id", ""))) or out["decor"].size() >= MAX_DECOR:
				continue
			var id := str(d["id"])
			if placed_count(out, id) >= int(out["owned"].get(id, 0)):
				continue
			var c := Vector2i(int(d.get("x", -1)), int(d.get("y", -1)))
			if blocked_reason(out, c) == "":
				out["decor"].append({"id": id, "x": c.x, "y": c.y, "rot": clampi(int(d.get("rot", 0)), 0, 3), "flip": bool(d.get("flip", false))})
	return out


static func theme_for_element(el: String) -> String:
	for t in THEMES:
		if THEMES[t]["element"] == el:
			return t
	return ""


static func summary(layout: Dictionary) -> String:
	var st: Array = []
	for s in STATIONS:
		st.append("%s@%s" % [s, layout["stations"][s]])
	return "theme %s, unlocked %s, %d/%d decorations, owned %s, stations %s" % [layout["theme"], layout["unlocked"],
		layout["decor"].size(), MAX_DECOR, layout["owned"], ", ".join(st)]
