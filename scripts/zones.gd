class_name Zones
## Static zone definitions: names, level ranges, portals, monster spawns, bosses.
## Every peer builds every zone's map locally from these (deterministic), but a
## client only *receives* players/monsters/loot of the zone it is in.

## Size of private instances (dungeons, hideouts) and of the original 64x40 overworld layout,
## which now survives as the "core" (entrance area) of each much bigger overworld zone.
const W := 64
const H := 40
## Overworld zones: 360x224 tiles ≈ 31.5× the area of the old 64×40 maps
## (≈ 3.15× the previous 200×128 wilds). Cores stay at the same anchors so map_v 2
## positions in town / near portals stay valid; wilderness and bosses stretch further out.
const BIG_W := 360
const BIG_H := 224
const TILE := 32
## Zones live side by side in world space (each with its own physics bodies),
## far enough apart that they never interact (a big zone is 11520 px wide).
const OFFSET_STEP := 16384.0
## Saves written before the first big maps have no "map_v"; their positions are in core coordinates.
## map_v 2 was the 200×128 maps; map_v 3 is 360×224 with the same core anchors.
const MAP_VERSION := 3
## First map_v that already stores big-map (not 64×40) coordinates.
const BIGMAP_SINCE := 2

const ORDER := ["meadow", "forest", "crypt", "frost"]

## Dungeon instances (see dungeons.gd) are added at runtime: id ("dun<N>") -> zone def.
static var DYN := {}
## Where players arrive in town when leaving a dungeon (next to the Map Device).
const TOWN_ARRIVE := Vector2i(165, 63)

## Monster groups (see zone.gd):
##   pack   - same type
##   nest   - dense same-type clutch (carved tight)
##   camp   - types[0] leads the others around a camp fire
##   horde  - large mixed pack (no leader bonus)
##   elite  - an elite + minions, better loot
##   patrol - walks between sites
##   guard  - around the boss lair
## "core": placed in the old entrance area; otherwise at generated sites, and
## "depth" [min, max] = how far from the entrance (0..1) the site may be. Levels scale with depth.
const DB := {
	"meadow": {
		"name": "Sunny Meadow", "short": "Meadow", "levels": "1-4", "safe": true, "lv": [1, 4],
		"core": Vector2i(136, 44),
		"respawn": Vector2i(168, 64),
		"blacksmith": Vector2i(172, 61),
		"map_device": Vector2i(165, 59),
		"merchant": Vector2i(160, 62),
		"vendor": Vector2i(156, 66),
		"hideout_master": Vector2i(176, 66),
		"map_portal_row": 56,
		## Walled starter village around the NPCs (absolute cells). No wild packs spawn inside.
		"town": {"name": "Sunnyhaven", "rect": Rect2i(152, 52, 30, 22)},
		"portals": [
			# Inside the 2-tile solid border (x = BIG_W-4) so roads can reach the gate.
			{"rect": Rect2i(356, 63, 2, 4), "to": "forest", "arrive": Vector2i(4, 20)},
		],
		"groups": [
			{"kind": "pack", "types": ["slime"], "size": [2, 3], "n": 5, "core": true},
			{"kind": "pack", "types": ["mossling"], "size": [2, 3], "n": 2, "core": true},
			{"kind": "pack", "types": ["slime"], "size": [3, 5], "n": 6, "depth": [0.0, 0.45]},
			{"kind": "nest", "types": ["slime"], "size": [5, 7], "n": 3, "depth": [0.1, 0.5]},
			{"kind": "pack", "types": ["mossling"], "size": [3, 5], "n": 5, "depth": [0.15, 0.7]},
			{"kind": "pack", "types": ["boar"], "size": [3, 4], "n": 5, "depth": [0.25, 0.85]},
			{"kind": "pack", "types": ["wolf"], "size": [3, 5], "n": 4, "depth": [0.35, 0.95]},
			{"kind": "nest", "types": ["wasp"], "size": [4, 6], "n": 3, "depth": [0.3, 0.8]},
			{"kind": "camp", "types": ["bandit", "bandit", "boar"], "size": [4, 5], "n": 3, "depth": [0.45, 0.9]},
			{"kind": "camp", "types": ["bandit", "wolf", "boar"], "size": [4, 6], "n": 3, "depth": [0.55, 1.0]},
			{"kind": "horde", "types": ["slime", "mossling", "boar"], "size": [6, 8], "n": 2, "depth": [0.5, 1.0]},
			{"kind": "elite", "types": ["boar", "mossling", "wolf"], "size": [3, 4], "n": 3, "depth": [0.65, 1.0]},
			{"kind": "elite", "types": ["bandit", "wasp"], "size": [3, 4], "n": 2, "depth": [0.75, 1.0]},
			{"kind": "patrol", "types": ["bandit", "boar"], "size": [3, 3], "n": 3, "depth": [0.25, 0.85]},
			{"kind": "patrol", "types": ["wolf", "mossling"], "size": [3, 4], "n": 2, "depth": [0.4, 0.95]},
		],
		"boss": {},
	},
	"forest": {
		"name": "Whisperwood Forest", "short": "Forest", "levels": "3-7", "lv": [3, 7],
		"core": Vector2i(0, 0),
		"respawn": Vector2i(5, 20),
		"portals": [
			{"rect": Rect2i(2, 19, 2, 4), "to": "meadow", "arrive": Vector2i(354, 64)},
			{"rect": Rect2i(30, 2, 4, 2), "to": "crypt", "arrive": Vector2i(168, 217)},
		],
		"groups": [
			{"kind": "pack", "types": ["rat"], "size": [3, 3], "n": 3, "core": true},
			{"kind": "pack", "types": ["bat"], "size": [3, 3], "n": 2, "core": true},
			{"kind": "pack", "types": ["spider"], "size": [2, 2], "n": 1, "core": true},
			{"kind": "pack", "types": ["rat"], "size": [4, 6], "n": 5, "depth": [0.0, 0.55]},
			{"kind": "nest", "types": ["bat"], "size": [5, 7], "n": 3, "depth": [0.1, 0.6]},
			{"kind": "pack", "types": ["bat"], "size": [3, 5], "n": 4, "depth": [0.15, 0.75]},
			{"kind": "pack", "types": ["spider"], "size": [3, 5], "n": 5, "depth": [0.25, 0.9]},
			{"kind": "nest", "types": ["spider"], "size": [5, 7], "n": 3, "depth": [0.4, 0.95]},
			{"kind": "pack", "types": ["wolf"], "size": [3, 5], "n": 4, "depth": [0.3, 0.85]},
			{"kind": "camp", "types": ["spider", "rat", "bat"], "size": [4, 5], "n": 3, "depth": [0.4, 0.9]},
			{"kind": "camp", "types": ["treant", "spider", "wolf"], "size": [4, 6], "n": 3, "depth": [0.55, 1.0]},
			{"kind": "horde", "types": ["rat", "spider", "bat", "wolf"], "size": [6, 9], "n": 3, "depth": [0.5, 1.0]},
			{"kind": "elite", "types": ["spider", "rat", "treant"], "size": [3, 4], "n": 3, "depth": [0.6, 1.0]},
			{"kind": "elite", "types": ["treant", "wolf"], "size": [3, 4], "n": 2, "depth": [0.75, 1.0]},
			{"kind": "patrol", "types": ["rat", "spider"], "size": [3, 4], "n": 3, "depth": [0.2, 0.85]},
			{"kind": "patrol", "types": ["wolf", "bat"], "size": [3, 4], "n": 2, "depth": [0.35, 0.95]},
			{"kind": "guard", "types": ["spider", "treant"], "size": [4, 4], "n": 1},
		],
		"boss": {"type": "broodmother", "level": 8, "cell": Vector2i(330, 190)},
	},
	"crypt": {
		"name": "Bone Crypt", "short": "Crypt", "levels": "6-11", "lv": [6, 11],
		"core": Vector2i(136, 88),
		"respawn": Vector2i(168, 122),
		"portals": [
			# Crypt outer terrain is solid wall — portals sit inside the border and get
			# road-linked in zone_map._gen_sites so they stay reachable from the entrance.
			{"rect": Rect2i(166, 220, 4, 2), "to": "forest", "arrive": Vector2i(32, 6)},
			{"rect": Rect2i(356, 107, 2, 4), "to": "frost", "arrive": Vector2i(6, 64)},
		],
		"groups": [
			{"kind": "pack", "types": ["archer"], "size": [2, 2], "n": 2, "core": true},
			{"kind": "pack", "types": ["ghost"], "size": [2, 3], "n": 2, "core": true},
			{"kind": "pack", "types": ["crawler"], "size": [2, 2], "n": 1, "core": true},
			{"kind": "pack", "types": ["archer"], "size": [3, 4], "n": 4, "depth": [0.0, 0.6]},
			{"kind": "pack", "types": ["ghost"], "size": [3, 5], "n": 4, "depth": [0.1, 0.7]},
			{"kind": "nest", "types": ["ghost"], "size": [5, 7], "n": 3, "depth": [0.2, 0.75]},
			{"kind": "pack", "types": ["crawler"], "size": [3, 4], "n": 4, "depth": [0.25, 0.9]},
			{"kind": "pack", "types": ["skeleton"], "size": [3, 5], "n": 4, "depth": [0.3, 0.85]},
			{"kind": "nest", "types": ["skeleton"], "size": [5, 7], "n": 2, "depth": [0.45, 0.95]},
			{"kind": "camp", "types": ["crawler", "archer", "archer", "ghost"], "size": [4, 5], "n": 3, "depth": [0.4, 0.9]},
			{"kind": "camp", "types": ["crawler", "skeleton", "wraith"], "size": [4, 6], "n": 3, "depth": [0.55, 1.0]},
			{"kind": "horde", "types": ["ghost", "skeleton", "archer"], "size": [6, 9], "n": 3, "depth": [0.5, 1.0]},
			{"kind": "elite", "types": ["crawler", "ghost", "archer"], "size": [3, 4], "n": 3, "depth": [0.6, 1.0]},
			{"kind": "elite", "types": ["wraith", "skeleton"], "size": [3, 4], "n": 2, "depth": [0.75, 1.0]},
			{"kind": "patrol", "types": ["ghost", "archer"], "size": [3, 3], "n": 3, "depth": [0.2, 0.85]},
			{"kind": "patrol", "types": ["skeleton", "wraith"], "size": [3, 4], "n": 2, "depth": [0.4, 0.95]},
			{"kind": "guard", "types": ["archer", "ghost", "wraith"], "size": [4, 4], "n": 1},
		],
		"boss": {"type": "lich", "level": 12, "cell": Vector2i(24, 16)},
	},
	"frost": {
		"name": "Frostpeak Ruins", "short": "Frost", "levels": "9-13", "lv": [9, 13],
		"core": Vector2i(0, 44),
		"respawn": Vector2i(5, 64),
		"portals": [
			# Arrive on the crypt east portal pad (outer crypt is solid wall; only roads + pads are walkable).
			{"rect": Rect2i(2, 63, 2, 4), "to": "crypt", "arrive": Vector2i(356, 109)},
		],
		"groups": [
			{"kind": "pack", "types": ["yeti"], "size": [2, 3], "n": 3, "core": true},
			{"kind": "pack", "types": ["ice_ogre"], "size": [1, 2], "n": 1, "core": true},
			{"kind": "pack", "types": ["frost_bat"], "size": [3, 3], "n": 2, "core": true},
			{"kind": "pack", "types": ["yeti"], "size": [3, 5], "n": 5, "depth": [0.0, 0.6]},
			{"kind": "nest", "types": ["frost_bat"], "size": [5, 7], "n": 3, "depth": [0.1, 0.65]},
			{"kind": "pack", "types": ["frost_bat"], "size": [3, 5], "n": 4, "depth": [0.15, 0.75]},
			{"kind": "pack", "types": ["ice_ogre"], "size": [2, 3], "n": 3, "depth": [0.35, 0.9]},
			{"kind": "pack", "types": ["ice_wolf"], "size": [3, 5], "n": 4, "depth": [0.25, 0.85]},
			{"kind": "nest", "types": ["snow_slime"], "size": [5, 7], "n": 2, "depth": [0.2, 0.7]},
			{"kind": "camp", "types": ["ice_ogre", "yeti", "yeti", "frost_bat"], "size": [4, 5], "n": 3, "depth": [0.4, 0.9]},
			{"kind": "camp", "types": ["ice_ogre", "ice_wolf", "yeti"], "size": [4, 6], "n": 3, "depth": [0.55, 1.0]},
			{"kind": "horde", "types": ["yeti", "frost_bat", "ice_wolf", "snow_slime"], "size": [6, 9], "n": 3, "depth": [0.5, 1.0]},
			{"kind": "elite", "types": ["yeti", "ice_ogre", "frost_bat"], "size": [3, 4], "n": 3, "depth": [0.6, 1.0]},
			{"kind": "elite", "types": ["ice_ogre", "ice_wolf"], "size": [3, 4], "n": 2, "depth": [0.75, 1.0]},
			{"kind": "patrol", "types": ["yeti", "frost_bat"], "size": [3, 4], "n": 3, "depth": [0.2, 0.85]},
			{"kind": "patrol", "types": ["ice_wolf", "yeti"], "size": [3, 4], "n": 2, "depth": [0.4, 0.95]},
			{"kind": "guard", "types": ["ice_ogre", "yeti", "ice_wolf"], "size": [4, 4], "n": 1},
		],
		"boss": {"type": "yeti_king", "level": 15, "cell": Vector2i(340, 30)},
	},
}


## Tile size of a zone: big for the overworld, 64x40 for instances.
static func size_of(id: String) -> Vector2i:
	return Vector2i(BIG_W, BIG_H) if DB.has(id) else Vector2i(W, H)


## Where the old 64x40 layout sits inside a big zone (Vector2i.ZERO for instances).
static func core_of(id: String) -> Vector2i:
	return DB[id]["core"] if DB.has(id) else Vector2i.ZERO


## Old saves (no "map_v" / map_v 1) stored positions on the 64x40 map: move them into the core.
## map_v >= BIGMAP_SINCE already uses big-map coordinates (cores stay put across 200→360 growth).
static func migrate_pos(id: String, pos: Vector2, map_v: int) -> Vector2:
	if map_v < BIGMAP_SINCE and DB.has(id):
		return pos + Vector2(core_of(id) * TILE)
	return pos


static func exists(id: String) -> bool:
	return DB.has(id) or DYN.has(id)


static func info(id: String) -> Dictionary:
	if DYN.has(id):
		return DYN[id]
	return DB.get(id, DB["meadow"])


static func is_dungeon(id: String) -> bool:
	return DYN.has(id) and DYN[id].has("dungeon")


## A player hideout instance ("ho<N>", see hideout_server.gd).
static func is_hideout(id: String) -> bool:
	return DYN.has(id) and DYN[id].has("hideout")


## World slot of a dynamic zone (dungeons and hideouts share the slots).
static func dyn_slot(id: String) -> int:
	var d: Dictionary = DYN[id]
	return int(d["dungeon"]["slot"]) if d.has("dungeon") else int(d.get("slot", 0))


## World-space slot of a zone (static zones first, then one slot per instance).
static func index_of(id: String) -> int:
	if DYN.has(id):
		return ORDER.size() + dyn_slot(id)
	return ORDER.find(id)
