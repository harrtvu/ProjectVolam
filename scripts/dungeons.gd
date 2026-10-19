class_name Dungeons
## Endgame dungeons (Path of Exile style "maps").
##
## A Dungeon Ticket is a gear-like item instance (see gear.gd) whose base is
## "ticket_<element>", plus {tier, q (quality)}. Its affixes are MAP MODIFIERS
## (stat keys "map_*") that make the run harder; every modifier adds item
## quantity / rarity to the run. Crafting orbs work on tickets like on gear.
##
## Opening a ticket at the Map Device creates a private INSTANCE: a dynamic zone
## ("dun<N>") whose map is generated from a seed on every peer (rooms/corridors
## or caves, tiles by theme), filled by the server with monster packs, elites and
## a boss. Everything here is static/deterministic so all peers agree.

const ORDER := ["wood", "water", "earth", "fire", "metal"]
const MAX_TIER := 10          # tickets go up to T10
const MERCHANT_BASE := 3      # the merchant always sells T1-T3
const MERCHANT_MAX := 6       # atlas progress unlocks more, but never above T6
const PORTALS := 6            # portals per run
const MAX_QUALITY := 20
const CHISEL_STEP := 5

const THEMES := {
	"wood": {"name": "Forest Den", "layout": "cave", "boss": "den_matriarch",
		"pool": ["spider", "rat", "bat"], "tint": [0.85, 1.0, 0.85],
		"floor": ["F_GRASS", "F_GRASS", "F_GRASS2", "F_MUSHROOM"], "wall": ["F_PINE", "F_TREE", "F_OAK", "F_DEAD"],
		"decor": ["F_STUMP", "F_DEAD", "F_OAK"]},
	"water": {"name": "Frozen Vault", "layout": "rooms", "boss": "vault_warden",
		"pool": ["yeti", "frost_bat", "ghost"], "tint": [0.9, 0.97, 1.08],
		"floor": ["S_FLOOR", "S_FLOOR", "S_ICE", "S_SNOW2"], "wall": ["S_WALL"],
		"decor": ["S_ROCK", "S_SNOWMAN", "S_PINE2"]},
	"earth": {"name": "Stone Hollow", "layout": "rooms", "boss": "crypt_lord",
		"pool": ["crawler", "ghost", "archer"], "tint": [1.0, 0.92, 0.8],
		"floor": ["C_FLOOR", "C_FLOOR", "C_FLOOR2", "C_RUBBLE"], "wall": ["C_WALL", "C_WALL", "C_WALL_SKULL", "C_WALL_GRATE"],
		"decor": ["C_TOMB", "C_GRAVE", "C_PILLAR"]},
	"fire": {"name": "Ember Caverns", "layout": "cave", "boss": "ember_tyrant",
		"pool": ["crawler", "bat", "spider"], "tint": [1.3, 0.72, 0.5],
		"floor": ["C_SAND", "C_FLOOR", "C_RUBBLE", "C_FLOOR2"], "wall": ["C_WALL"],
		"decor": ["C_BARREL", "C_ALTAR", "WATER"]},
	"metal": {"name": "Metal Forge", "layout": "rooms", "boss": "forge_golem",
		"pool": ["archer", "frost_bat", "ice_ogre"], "tint": [0.82, 0.9, 1.1],
		"floor": ["FLOOR", "FLOOR", "C_FLOOR2"], "wall": ["WALL"],
		"decor": ["C_PILLAR", "C_BARREL", "C_ALTAR"]},
}

## What one modifier is worth: [iiq, iir] for tier index 0/1/2 (unique mods: fixed).
const MOD_IIQ := [4, 6, 9]
const MOD_IIR := [6, 10, 15]

## Elite (rare monster) modifiers.
const ELITE_MODS := ["hasted", "armoured", "brutal", "regenerating"]
const ELITE_NAMES := {"hasted": "Hasted", "armoured": "Armoured", "brutal": "Brutal", "regenerating": "Regenerating"}


static func is_theme(t: String) -> bool:
	return THEMES.has(t)


static func theme_name(t: String) -> String:
	return str(THEMES.get(t, THEMES["wood"])["name"])


## Monster level inside a tier-N dungeon.
## T1 tuning (a fresh Lv6 must survive the first pull): monsters hit for x0.8 (not the boss),
## and every pack within T1_FIRST_PULL_RADIUS px of the entrance is a pair (1200 px: a fresh Lv6
## running in pulls 5-8 packs in its first 20 s; at 800 px the packs just past it did the damage).
const T1_DMG_MULT := 0.8
const T1_FIRST_PULL_RADIUS := 1200.0
## The warm-up packs (within T1_FIRST_PULL_RADIUS of a T1 entrance) hit softer still, so a fresh
## Lv6 on the real kit (3 Health Potions) survives its first pull; the rest of T1 is unchanged.
const T1_WARMUP_DMG_MULT := 0.6
const T1_WARMUP_HP_MULT := 1.0
const T1_WARMUP_PACKS := 99   # cap on how many of the nearest packs are warm-up (99 = every pack inside the radius; 8 tested: 26/30)


static func level(tier: int) -> int:
	return 4 + 2 * tier


## Item level of a ticket (gates which map-modifier tiers can roll).
static func ticket_ilvl(tier: int) -> int:
	return tier * 2


static func is_ticket(inst: Dictionary) -> bool:
	return str(inst.get("base", "")).begins_with("ticket_")


static func theme_of(inst: Dictionary) -> String:
	return str(inst.get("base", "ticket_wood")).trim_prefix("ticket_")


static func tier_of(inst: Dictionary) -> int:
	return clampi(int(inst.get("tier", 1)), 1, MAX_TIER)


static func make_ticket(theme: String, tier: int, rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	tier = clampi(tier, 1, MAX_TIER)
	var inst := Gear.make("ticket_" + theme, "normal", ticket_ilvl(tier), rng)
	inst["tier"] = tier
	inst["q"] = 0
	if rarity != "normal":
		inst["rarity"] = rarity
		Gear._roll_affixes(inst, rng, "")
	return inst


static func make_unique_ticket(uid_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var u: Dictionary = Items.UNIQUES[uid_id]
	var inst := Gear.make_unique(uid_id, ticket_ilvl(int(u["tier"])), rng)
	inst["tier"] = int(u["tier"])
	inst["q"] = 0
	return inst


## The run's map modifiers (stat -> value) and its total item quantity / rarity bonus.
static func run_info(inst: Dictionary) -> Dictionary:
	var mods := {}
	var iiq := 0.0
	var iir := 0.0
	for e in inst.get("mods", []):
		var st := str(e[1])
		mods[st] = float(mods.get(st, 0.0)) + float(e[2])
		if str(e[4]) == "u":
			iiq += 8.0
			iir += 12.0
		else:
			var t := clampi(int(e[3]), 0, 2)
			iiq += MOD_IIQ[t]
			iir += MOD_IIR[t]
	iiq += float(clampi(int(inst.get("q", 0)), 0, MAX_QUALITY))
	return {"mods": mods, "iiq": iiq, "iir": iir}


static func mod_text(stat: String, v: float) -> String:
	match stat:
		"map_mon_hp": return "Monsters have %d%% more life" % v
		"map_mon_dmg": return "Monsters deal %d%% more damage" % v
		"map_extra_ele": return "Monsters deal %d%% extra damage as their element" % v
		"map_packs": return "%d%% more monster packs" % v
		"map_elites": return "%d extra elite pack%s" % [v, "s" if v != 1 else ""]
		"map_mon_speed": return "Monsters move %d%% faster" % v
		"map_less_res": return "Players have -%d%% to all elemental resistances" % v
		"map_no_regen": return "Players cannot regenerate life"
		"map_less_mana_regen": return "Players have %d%% less mana regeneration" % v
		"map_mon_def": return "Monsters have +%d defense" % v
	return "%s %s" % [stat, v]


## Tooltip lines for a ticket ([[text, Color], ...]).
static func tooltip(inst: Dictionary, atlas: Dictionary = {}) -> Array:
	var out: Array = []
	var theme := theme_of(inst)
	var tier := tier_of(inst)
	var col: Color = Gear.RARITY_COLOR.get(str(inst.get("rarity", "normal")), Color.WHITE)
	out.append([Gear.display_name(inst), col])
	out.append(["%s Dungeon Ticket  -  %s  -  Tier %d" % [str(inst.get("rarity", "normal")).capitalize(), theme_name(theme), tier], Color(0.7, 0.7, 0.75)])
	out.append(["Element: %s (monsters and boss)   Monster level %d" % [Classes.ELEMENT_INFO[theme]["name"], level(tier)], Classes.color(theme).lerp(Color.WHITE, 0.35)])
	var ri := run_info(inst)
	var q := int(inst.get("q", 0))
	out.append(["Item quantity: +%d%%   Item rarity: +%d%%%s" % [ri["iiq"], ri["iir"], ("   (quality %d%%)" % q) if q > 0 else ""], Color(1.0, 0.9, 0.5)])
	if inst.get("mods", []).is_empty():
		out.append(["No modifiers (use a Transmutation / Alteration / Regal / Chaos / Exalted Orb)", Color(0.6, 0.6, 0.65)])
	for e in inst.get("mods", []):
		var tag := "" if str(e[4]) == "u" else ("  (%s T%d)" % ["prefix" if e[4] == "p" else "suffix", int(e[3]) + 1])
		out.append([mod_text(str(e[1]), float(e[2])) + tag, Color(0.55, 0.7, 1.0) if str(e[4]) != "u" else Color(1.0, 0.7, 0.35)])
	if inst.get("rarity") == "unique":
		out.append([str(Items.UNIQUES.get(str(inst.get("uniq", "")), {}).get("flavour", "")), Color(0.85, 0.5, 0.2)])
	out.append(["Open it at the Map Device in Sunny Meadow: %d portals, private instance, boss at the end." % PORTALS, Color(0.7, 0.7, 0.75)])
	if not atlas.is_empty():
		var best := best_tier(atlas, theme)
		out.append(["Atlas: best %s completed = %s" % [theme_name(theme), ("T%d" % best) if best > 0 else "none"], Color(0.7, 0.85, 0.7)])
	out.append(["Sells for %d gold" % Gear.sell_price(inst), Color(0.85, 0.75, 0.4)])
	return out


# ---------------------------------------------------------------- atlas / merchant

## atlas = {"done": {"wood:3": runs, ...}}
static func best_tier(atlas: Dictionary, theme: String) -> int:
	var best := 0
	var done: Dictionary = atlas.get("done", {})
	for k in done:
		if str(k).get_slice(":", 0) == theme:
			best = maxi(best, int(str(k).get_slice(":", 1)))
	return best


static func completed_nodes(atlas: Dictionary) -> int:
	return atlas.get("done", {}).size()


## Atlas bonus: +1% item quantity inside dungeons per distinct theme/tier completed (max 30%).
static func atlas_iiq(atlas: Dictionary) -> float:
	return minf(30.0, float(completed_nodes(atlas)))


## Highest tier the merchant sells for a theme: T1-T3 always, then one above your best completion (max T6).
static func merchant_max(atlas: Dictionary, theme: String) -> int:
	return Atlas.merchant_max(atlas, theme)


static func price(tier: int) -> int:
	return 25 + 35 * tier * tier


static func sanitize_atlas(v: Variant) -> Dictionary:
	return Atlas.sanitize(v)


# ---------------------------------------------------------------- layout (deterministic)

## Rooms + their visiting order. Returns {"rooms": [Rect2i], "order": [idx], "cave": bool}.
static func layout(seed: int, theme: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var W := Zones.W
	var H := Zones.H
	var rooms: Array = []
	for attempt in 400:
		if rooms.size() >= 10:
			break
		var w := r.randi_range(8, 13)
		var h := r.randi_range(7, 10)
		var rect := Rect2i(r.randi_range(3, W - 3 - w), r.randi_range(3, H - 3 - h), w, h)
		var ok := true
		for o in rooms:
			if (o as Rect2i).grow(2).intersects(rect):
				ok = false
				break
		if ok:
			rooms.append(rect)
	# start = left-most room; then greedy nearest-neighbour chain -> boss = last room
	var start := 0
	for i in rooms.size():
		if rooms[i].get_center().x < rooms[start].get_center().x:
			start = i
	var order: Array = [start]
	var left: Array = []
	for i in rooms.size():
		if i != start:
			left.append(i)
	while not left.is_empty():
		var cur: Vector2 = Vector2(rooms[order[-1]].get_center())
		var bi := 0
		for j in left.size():
			if Vector2(rooms[left[j]].get_center()).distance_to(cur) < Vector2(rooms[left[bi]].get_center()).distance_to(cur):
				bi = j
		order.append(left[bi])
		left.remove_at(bi)
	return {"rooms": rooms, "order": order, "cave": THEMES[theme]["layout"] == "cave", "loop_seed": r.randi()}


## Builds the zone definition (Zones-style dict) for an instance. Same on every peer.
static func make_def(id: String, theme: String, tier: int, seed: int, slot: int, mods: Dictionary, owner: String) -> Dictionary:
	var lay := layout(seed, theme)
	var rooms: Array = lay["rooms"]
	var order: Array = lay["order"]
	var start: Rect2i = rooms[order[0]]
	var c := start.get_center()
	var boss_room: Rect2i = rooms[order[-1]]
	return {
		"name": "%s (T%d)" % [theme_name(theme), tier], "short": "%s T%d" % [theme_name(theme).get_slice(" ", 1), tier],
		"levels": str(level(tier)),
		"respawn": c + Vector2i(1, 0),
		"portals": [{"rect": Rect2i(c.x - 3, c.y - 1, 2, 2), "to": "meadow", "arrive": Zones.TOWN_ARRIVE}],
		"monsters": [], "boss": {},
		"dungeon": {"theme": theme, "tier": tier, "seed": seed, "slot": slot, "mods": mods, "owner": owner,
			"rooms": rooms, "order": order, "cave": lay["cave"], "loop_seed": lay["loop_seed"], "boss_cell": boss_room.get_center()},
	}


static func tile(name: String) -> Vector2i:
	return _TILE_LOOKUP.get(name, Vector2i(0, 0))


const _TILE_LOOKUP := {
	"F_GRASS": Tiles.F_GRASS, "F_GRASS2": Tiles.F_GRASS2, "F_MUSHROOM": Tiles.F_MUSHROOM, "F_PINE": Tiles.F_PINE,
	"F_TREE": Tiles.F_TREE, "F_OAK": Tiles.F_OAK, "F_DEAD": Tiles.F_DEAD, "F_STUMP": Tiles.F_STUMP,
	"S_FLOOR": Tiles.S_FLOOR, "S_ICE": Tiles.S_ICE, "S_SNOW2": Tiles.S_SNOW2, "S_WALL": Tiles.S_WALL,
	"S_ROCK": Tiles.S_ROCK, "S_SNOWMAN": Tiles.S_SNOWMAN, "S_PINE2": Tiles.S_PINE2,
	"C_FLOOR": Tiles.C_FLOOR, "C_FLOOR2": Tiles.C_FLOOR2, "C_RUBBLE": Tiles.C_RUBBLE, "C_WALL": Tiles.C_WALL,
	"C_WALL_SKULL": Tiles.C_WALL_SKULL, "C_WALL_GRATE": Tiles.C_WALL_GRATE, "C_TOMB": Tiles.C_TOMB, "C_GRAVE": Tiles.C_GRAVE,
	"C_PILLAR": Tiles.C_PILLAR, "C_BARREL": Tiles.C_BARREL, "C_ALTAR": Tiles.C_ALTAR, "C_SAND": Tiles.C_SAND,
	"FLOOR": Tiles.FLOOR, "WALL": Tiles.WALL, "WATER": Tiles.WATER,
}


# ---------------------------------------------------------------- loot

## Ticket drop inside a dungeon (or from tough overworld monsters). theme "" = random.
static func roll_ticket(tier: int, iir: float, rng: RandomNumberGenerator, theme := "") -> Dictionary:
	if theme == "":
		theme = ORDER[rng.randi() % ORDER.size()]
	var rarity := Gear.roll_rarity(rng, iir)
	if rarity == "unique":
		if tier >= 6 and rng.randf() < 0.5:
			return make_unique_ticket("wuxing_sanctum", rng)
		rarity = "rare"
	return make_ticket(theme, tier, rarity, rng)
