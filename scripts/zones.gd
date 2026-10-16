class_name Zones
## Static zone definitions: names, level ranges, portals, monster spawns, bosses.
## Every peer builds every zone's map locally from these (deterministic), but a
## client only *receives* players/monsters/loot of the zone it is in.

const W := 64
const H := 40
const TILE := 32
## Zones live side by side in world space (each with its own physics bodies),
## far enough apart that they never interact.
const OFFSET_STEP := 4096.0

const ORDER := ["meadow", "forest", "crypt", "frost"]

## Dungeon instances (see dungeons.gd) are added at runtime: id ("dun<N>") -> zone def.
static var DYN := {}
## Where players arrive in town when leaving a dungeon (next to the Map Device).
const TOWN_ARRIVE := Vector2i(29, 19)

const DB := {
	"meadow": {
		"name": "Sunny Meadow", "short": "Meadow", "levels": "1-3", "safe": true,
		"respawn": Vector2i(32, 20),
		"blacksmith": Vector2i(36, 17),   # anvil + stash; enhancement / selling / stash work within 100px
		"map_device": Vector2i(29, 15),   # opens dungeon tickets; portals appear in a row above it
		"merchant": Vector2i(24, 18),     # Ticket Merchant: sells low-tier tickets, daily free ticket
		"broker": Vector2i(20, 22),       # Trade Broker: player market (list / buy / claim box)
		"map_portal_row": 12,
		"portals": [
			{"rect": Rect2i(62, 19, 2, 4), "to": "forest", "arrive": Vector2i(4, 20)},
		],
		"monsters": [
			{"type": "slime", "count": 10, "lv": [1, 2]},
		],
		"boss": {},
	},
	"forest": {
		"name": "Whisperwood Forest", "short": "Forest", "levels": "3-6",
		"respawn": Vector2i(5, 20),
		"portals": [
			{"rect": Rect2i(0, 19, 2, 4), "to": "meadow", "arrive": Vector2i(59, 20)},
			{"rect": Rect2i(30, 0, 4, 2), "to": "crypt", "arrive": Vector2i(32, 35)},
		],
		"monsters": [
			{"type": "rat", "count": 4, "pack": 3, "lv": [3, 5]},
			{"type": "bat", "count": 6, "lv": [3, 5]},
			{"type": "spider", "count": 5, "lv": [4, 6]},
		],
		"boss": {"type": "broodmother", "level": 8, "cell": Vector2i(50, 9)},
	},
	"crypt": {
		"name": "Bone Crypt", "short": "Crypt", "levels": "6-10",
		"respawn": Vector2i(32, 34),
		"portals": [
			{"rect": Rect2i(30, 38, 4, 2), "to": "forest", "arrive": Vector2i(32, 4)},
			{"rect": Rect2i(62, 19, 2, 4), "to": "frost", "arrive": Vector2i(4, 20)},
		],
		"monsters": [
			{"type": "archer", "count": 6, "lv": [6, 9]},
			{"type": "ghost", "count": 6, "lv": [6, 9]},
			{"type": "crawler", "count": 5, "lv": [7, 10]},
		],
		"boss": {"type": "lich", "level": 12, "cell": Vector2i(32, 6)},
	},
	"frost": {
		"name": "Frostpeak Ruins", "short": "Frost", "levels": "9-12",
		"respawn": Vector2i(5, 20),
		"portals": [
			{"rect": Rect2i(0, 19, 2, 4), "to": "crypt", "arrive": Vector2i(59, 20)},
		],
		"monsters": [
			{"type": "yeti", "count": 6, "lv": [9, 12]},
			{"type": "ice_ogre", "count": 4, "lv": [10, 12]},
			{"type": "frost_bat", "count": 5, "lv": [9, 11]},
		],
		"boss": {"type": "yeti_king", "level": 15, "cell": Vector2i(53, 20)},
	},
}


static func exists(id: String) -> bool:
	return DB.has(id) or DYN.has(id)


static func info(id: String) -> Dictionary:
	if DYN.has(id):
		return DYN[id]
	return DB.get(id, DB["meadow"])


static func is_dungeon(id: String) -> bool:
	return DYN.has(id)


## World-space slot of a zone (static zones first, then one slot per instance).
static func index_of(id: String) -> int:
	if DYN.has(id):
		return ORDER.size() + int(DYN[id]["dungeon"]["slot"])
	return ORDER.find(id)
