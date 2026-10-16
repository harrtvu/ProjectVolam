class_name Atlas
## Path-of-Exile-style Atlas: a world map of named dungeon nodes + the atlas passive tree.
##
## Node ids are "<theme>:<tier>" (same keys the old 5x10 atlas grid used, so old saves
## migrate cleanly) plus "pinnacle" (Ngu Hanh, the Five Elements, at the centre).
## Five elemental regions sit around a central pentagon; each region is a chain
## T1 -> T2 -> T3 -> T5 -> T7 -> Guardian (T10) running from the outer ring inwards,
## with ring paths between neighbouring regions at T2 and T5. T1 nodes start open;
## a node becomes available once an adjacent node is completed. The pinnacle needs
## all five Guardians. Everything here is static/pure so server, client and the
## offline self-test agree. The server is the only one that ever changes atlas data.

const REGION_TIERS := [1, 2, 3, 5, 7, 10]
const GUARDIAN_TIER := 10
const PINNACLE := "pinnacle"
const MERCHANT_CAP := 5          # merchant sells unlocked nodes up to T5
const RESPEC_GOLD_PER_POINT := 150

## unique-ish dungeon names per region, outer -> inner
const NAMES := {
	"wood": ["Mossgrown Den", "Thornback Warren", "Rootcoil Burrow", "Weeping Canopy", "Heartwood Lair", "Guardian of the Verdant Crown"],
	"water": ["Rimefrost Cellar", "Sunken Treasury", "Glacier Reliquary", "Drowned Archive", "Pale Tide Vault", "Guardian of the Abyssal Mirror"],
	"earth": ["Dustbone Hollow", "Sandglass Crypt", "Ossuary Deep", "Graven Labyrinth", "Mountain's Heart", "Guardian of the Jade Mountain"],
	"fire": ["Cinder Throat", "Ashen Gallery", "Smouldering Pit", "Magma Sanctum", "Phoenix Roost", "Guardian of the Eternal Flame"],
	"metal": ["Rustwork Foundry", "Bellows Hall", "Anvil Depths", "Quench Chambers", "Iron Crucible", "Guardian of the Celestial Blade"],
}

## bonus objectives ("bonus completion"), by node tier
const BONUS := {1: "rare", 2: "deathless", 3: "elites", 5: "rare", 7: "elites", 10: "deathless"}
const BONUS_TEXT := {"rare": "Complete it with a Rare or Unique ticket", "elites": "Slay every elite pack before the boss dies",
	"deathless": "Complete it without dying"}

static var _nodes := {}
static var _passives := {}


# ================================================================ map nodes

static func nodes() -> Dictionary:
	if _nodes.is_empty():
		_build_nodes()
	return _nodes


static func _build_nodes() -> void:
	var order: Array = Dungeons.ORDER
	var radius := {1: 560.0, 2: 465.0, 3: 380.0, 5: 300.0, 7: 225.0, 10: 140.0}
	for k in order.size():
		var th: String = order[k]
		var ang := deg_to_rad(-90.0 + 72.0 * k)
		for i in REGION_TIERS.size():
			var t: int = REGION_TIERS[i]
			var wob := deg_to_rad((9.0 if i % 2 == 0 else -9.0) if t != GUARDIAN_TIER and t != 1 else 0.0)
			var id := "%s:%d" % [th, t]
			_nodes[id] = {"id": id, "theme": th, "tier": t, "name": NAMES[th][i], "guardian": t == GUARDIAN_TIER,
				"pos": Vector2(cos(ang + wob), sin(ang + wob)) * radius[t], "bonus": BONUS[t],
				"seed": 7919 * (k + 1) + 104729 * (i + 1), "adj": []}
	_nodes[PINNACLE] = {"id": PINNACLE, "theme": "earth", "tier": GUARDIAN_TIER, "name": "Ngu Hanh - Sanctum of the Five Elements",
		"guardian": false, "pinnacle": true, "pos": Vector2.ZERO, "bonus": "deathless", "seed": 55555, "adj": []}
	for k in order.size():
		var th: String = order[k]
		var nx: String = order[(k + 1) % order.size()]
		for i in REGION_TIERS.size() - 1:
			_link("%s:%d" % [th, REGION_TIERS[i]], "%s:%d" % [th, REGION_TIERS[i + 1]])
		_link("%s:2" % th, "%s:2" % nx)
		_link("%s:5" % th, "%s:5" % nx)
		_link("%s:%d" % [th, GUARDIAN_TIER], PINNACLE)


static func _link(a: String, b: String) -> void:
	_nodes[a]["adj"].append(b)
	_nodes[b]["adj"].append(a)


static func has_node(id: String) -> bool:
	return nodes().has(id)


static func node(id: String) -> Dictionary:
	return nodes().get(id, {})


static func adjacent(id: String) -> Array:
	return node(id).get("adj", [])


static func display(id: String) -> String:
	var n := node(id)
	if n.is_empty():
		return id
	if n.get("pinnacle", false):
		return "%s (T%d, pinnacle)" % [n["name"], n["tier"]]
	return "%s - %s T%d" % [n["name"], Dungeons.theme_name(n["theme"]), n["tier"]]


## The node a ticket belongs to: its "node" field, else theme + the nearest region tier at or below its tier.
static func node_of_ticket(inst: Dictionary) -> String:
	var nid := str(inst.get("node", ""))
	if has_node(nid):
		return nid
	return snap(Dungeons.theme_of(inst), Dungeons.tier_of(inst))


static func snap(theme: String, tier: int) -> String:
	var best := 1
	for t in REGION_TIERS:
		if t <= tier:
			best = t
	return "%s:%d" % [theme, best]


static func is_done(atlas: Dictionary, id: String) -> bool:
	return int(atlas.get("done", {}).get(id, 0)) > 0


static func guardians_done(atlas: Dictionary) -> int:
	var n := 0
	for th in Dungeons.ORDER:
		if is_done(atlas, "%s:%d" % [th, GUARDIAN_TIER]):
			n += 1
	return n


## Can this node be run? T1 nodes always; others once an adjacent node is completed;
## the pinnacle once all five Guardians are.
static func is_available(atlas: Dictionary, id: String) -> bool:
	var n := node(id)
	if n.is_empty():
		return false
	if n.get("pinnacle", false):
		return guardians_done(atlas) >= 5
	if int(n["tier"]) == 1 or is_done(atlas, id):
		return true
	for a in n["adj"]:
		if a != PINNACLE and is_done(atlas, a):
			return true
	return false


## "completed" | "available" | "locked"
static func state(atlas: Dictionary, id: String) -> String:
	if is_done(atlas, id):
		return "completed"
	return "available" if is_available(atlas, id) else "locked"


## Highest tier the merchant sells for a theme: unlocked nodes up to T5 (T1 always).
static func merchant_max(atlas: Dictionary, theme: String) -> int:
	var best := 1
	for t in REGION_TIERS:
		if t <= MERCHANT_CAP and is_available(atlas, "%s:%d" % [theme, t]):
			best = t
	return best


static func merchant_sells(atlas: Dictionary, theme: String, tier: int) -> bool:
	return tier <= MERCHANT_CAP and REGION_TIERS.has(tier) and is_available(atlas, "%s:%d" % [theme, tier])


## Boss ticket target: with chance `adj_chance` a random ADJACENT node (sustain loop:
## you get tickets to push outward), else the node itself.
static func boss_ticket_node(id: String, rng: RandomNumberGenerator, adj_chance: float, prefer_up := false) -> String:
	var adj: Array = []
	for a in adjacent(id):
		if a != PINNACLE:
			adj.append(a)
	if adj.is_empty() or rng.randf() >= adj_chance:
		return id
	if prefer_up:
		var up: Array = adj.filter(func(a): return int(node(a)["tier"]) > int(node(id)["tier"]))
		if not up.is_empty():
			return up[rng.randi() % up.size()]
	return adj[rng.randi() % adj.size()]


## Ticket for a node (the ticket's tier is the node's tier).
static func make_node_ticket(id: String, rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var n := node(id)
	var t := Dungeons.make_ticket(str(n["theme"]), int(n["tier"]), rarity, rng)
	t["node"] = id
	return t


## Monster ticket drop for a node: same node, or (tier chance) an adjacent higher-tier node.
static func roll_drop_node(id: String, rng: RandomNumberGenerator, tier_up_pct: float) -> String:
	if rng.randf() < tier_up_pct / 100.0:
		var up: Array = adjacent(id).filter(func(a): return a != PINNACLE and int(node(a)["tier"]) > int(node(id)["tier"]))
		if not up.is_empty():
			return up[rng.randi() % up.size()]
	return id


# ================================================================ points / migration

static func points_earned(atlas: Dictionary) -> int:
	var n := 0
	for k in atlas.get("done", {}):
		n += 1
	n += atlas.get("bonus", {}).size()
	return n


static func points_spent(atlas: Dictionary) -> int:
	return atlas.get("passives", []).size()


static func points_free(atlas: Dictionary) -> int:
	return points_earned(atlas) - points_spent(atlas)


## Accepts both the new format and the old {"done": {"theme:tier": runs}} grid (any tier 1-10).
## Old keys that are not map nodes (T4, T6, T8, T9) migrate to the region node at or below.
static func sanitize(v: Variant) -> Dictionary:
	var out := {"v": 2, "done": {}, "bonus": {}, "passives": [], "migrated": []}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	if typeof(v.get("done")) == TYPE_DICTIONARY:
		for k in v["done"]:
			var key := str(k)
			var runs := maxi(1, int(v["done"][k]))
			if key == PINNACLE:
				out["done"][key] = int(out["done"].get(key, 0)) + runs
				continue
			var t := key.get_slice(":", 0)
			var n := int(key.get_slice(":", 1))
			if not Dungeons.is_theme(t) or n < 1 or n > Dungeons.MAX_TIER:
				continue
			var nid := snap(t, n)
			if nid != key:
				out["migrated"].append("%s->%s" % [key, nid])
			out["done"][nid] = int(out["done"].get(nid, 0)) + runs
	if typeof(v.get("bonus")) == TYPE_DICTIONARY:
		for k in v["bonus"]:
			if has_node(str(k)) and out["done"].has(str(k)):
				out["bonus"][str(k)] = true
	if v.get("v", 1) == 2 and typeof(v.get("migrated")) == TYPE_ARRAY and out["migrated"].is_empty():
		out["migrated"] = v["migrated"].duplicate()
	if typeof(v.get("passives")) == TYPE_ARRAY:
		var keep: Array = []
		for p in v["passives"]:
			var pid := str(p)
			if passives().has(pid) and not keep.has(pid) and keep.size() < points_earned(out) and _connected_to(keep, pid):
				keep.append(pid)
		out["passives"] = keep
	return out


static func is_legacy(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY and int(v.get("v", 1)) < 2 and not v.get("done", {}).is_empty()


# ================================================================ atlas passive tree

static func passives() -> Dictionary:
	if _passives.is_empty():
		_build_passives()
	return _passives


const SPECIAL := {   # per region: the arm's first node and its capstone
	"wood": [{"elites": 1}, {"elites": 1, "iiq": 5}, "Teeming Wilds", "Primal Hunt"],
	"water": [{"portals": 1}, {"portals": 1, "iir": 10}, "Tidal Gate", "Endless Tides"],
	"earth": [{"boss": 25}, {"boss": 25, "iir": 10}, "Tomb Raider", "Mountain King's Hoard"],
	"fire": [{"cur": 30}, {"cur": 30, "iiq": 5}, "Ember Coin", "Phoenix Treasury"],
	"metal": [{"tt": 15}, {"tt": 15, "tq": 10}, "Honed Compass", "Celestial Cartography"],
}


static func _build_passives() -> void:
	var order: Array = Dungeons.ORDER
	_passives["a_root"] = {"name": "Atlas Heart", "fx": {}, "pos": Vector2.ZERO, "adj": [], "kind": "root"}
	for k in order.size():
		var th: String = order[k]
		var en: String = Classes.ELEMENT_INFO[th]["name"]
		var ang := deg_to_rad(-90.0 + 72.0 * k)
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		var sp: Array = SPECIAL[th]
		_add_p("a_ring_" + th, "Cartographer's Insight", {"iiq": 3, "iir": 5}, dir * 90.0, "small")
		_add_p("a_%s_1" % th, sp[2], sp[0], dir * 170.0 + side * 40.0, "small")
		_add_p("a_%s_2" % th, "Ticket Hoarder", {"tq": 12}, dir * 170.0 - side * 40.0, "small")
		_add_p("a_%s_3" % th, "%s Attunement" % en, {"reg_" + th: 12}, dir * 250.0, "small")
		_add_p("a_%s_4" % th, "%s Dominion" % en, {"reg_" + th: 25, "tq": 10}, dir * 330.0 - side * 35.0, "notable")
		_add_p("a_%s_5" % th, sp[3], sp[1], dir * 330.0 + side * 45.0, "notable")
		_plink("a_root", "a_ring_" + th)
		_plink("a_ring_" + th, "a_%s_1" % th)
		_plink("a_ring_" + th, "a_%s_2" % th)
		_plink("a_%s_1" % th, "a_%s_3" % th)
		_plink("a_%s_2" % th, "a_%s_3" % th)
		_plink("a_%s_3" % th, "a_%s_4" % th)
		_plink("a_%s_3" % th, "a_%s_5" % th)
	for k in order.size():
		var th: String = order[k]
		var nx: String = order[(k + 1) % order.size()]
		var a: Vector2 = _passives["a_%s_2" % th]["pos"]
		var b: Vector2 = _passives["a_%s_1" % nx]["pos"]
		_add_p("a_cross_" + th, "Wayfarer's Fortune", {"iiq": 4, "iir": 4}, (a + b) * 0.5 * 1.25, "small")
		_plink("a_%s_2" % th, "a_cross_" + th)
		_plink("a_cross_" + th, "a_%s_1" % nx)


static func _add_p(id: String, name: String, fx: Dictionary, pos: Vector2, kind: String) -> void:
	_passives[id] = {"name": name, "fx": fx, "pos": pos, "adj": [], "kind": kind}


static func _plink(a: String, b: String) -> void:
	_passives[a]["adj"].append(b)
	_passives[b]["adj"].append(a)


## A passive can be taken when it is adjacent to the root or to an allocated passive.
static func _connected_to(alloc: Array, pid: String) -> bool:
	for a in passives()[pid]["adj"]:
		if a == "a_root" or alloc.has(a):
			return true
	return false


## "" if allocation is allowed, else the reason.
static func can_allocate(atlas: Dictionary, pid: String) -> String:
	if not passives().has(pid) or pid == "a_root":
		return "there is no atlas passive '%s'" % pid
	var alloc: Array = atlas.get("passives", [])
	if alloc.has(pid):
		return "%s is already allocated" % passives()[pid]["name"]
	if points_free(atlas) <= 0:
		return "no atlas points left (%d earned, %d spent)" % [points_earned(atlas), points_spent(atlas)]
	if not _connected_to(alloc, pid):
		return "%s is not connected to your atlas passives" % passives()[pid]["name"]
	return ""


static func fx_text(fx: Dictionary) -> String:
	var parts: Array = []
	for k in fx:
		var v := int(fx[k])
		match str(k):
			"iiq": parts.append("+%d%% item quantity in dungeons" % v)
			"iir": parts.append("+%d%% item rarity in dungeons" % v)
			"tq": parts.append("+%d%% Dungeon Ticket drop chance" % v)
			"tt": parts.append("+%d%% chance dropped tickets are for a higher-tier adjacent node" % v)
			"elites": parts.append("+%d elite pack per dungeon" % v)
			"portals": parts.append("+%d portal per dungeon" % v)
			"boss": parts.append("+%d%% boss loot (extra rare items and tickets)" % v)
			"cur": parts.append("+%d%% crafting currency drops in dungeons" % v)
			_:
				var th := str(k).trim_prefix("reg_")
				parts.append("%s region (%s) dungeons: +%d%% item quantity and rarity, +%d%% chance of an extra loot roll per kill" % [Classes.ELEMENT_INFO[th]["name"], Dungeons.theme_name(th), v, v])
	return "\n".join(parts)


## Sum of allocated passive effects.
static func effects(atlas: Dictionary) -> Dictionary:
	var out := {}
	for pid in atlas.get("passives", []):
		var fx: Dictionary = passives().get(str(pid), {}).get("fx", {})
		for k in fx:
			out[k] = float(out.get(k, 0.0)) + float(fx[k])
	return out


## Effects that apply to one run (theme): generic + that region's boost folded into iiq/iir.
static func run_effects(atlas: Dictionary, theme: String) -> Dictionary:
	var e := effects(atlas)
	var out := {}
	for k in ["iiq", "iir", "tq", "tt", "elites", "portals", "boss", "cur"]:
		out[k] = float(e.get(k, 0.0))
	var reg := float(e.get("reg_" + theme, 0.0))
	out["reg"] = reg
	out["iiq"] += reg
	out["iir"] += reg
	return out


static func respec_cost(atlas: Dictionary) -> int:
	return points_spent(atlas) * RESPEC_GOLD_PER_POINT


## Bonus objective check at completion. run: {rarity, deaths, elites_total, elites_killed}
static func bonus_met(id: String, run: Dictionary) -> bool:
	match str(node(id).get("bonus", "")):
		"rare":
			return str(run.get("rarity", "normal")) in ["rare", "unique"]
		"elites":
			return int(run.get("elites_killed", 0)) >= int(run.get("elites_total", 0))
		"deathless":
			return int(run.get("deaths", 0)) == 0
	return false


static func bonus_text(id: String) -> String:
	return str(BONUS_TEXT.get(str(node(id).get("bonus", "")), ""))


# ================================================================ server-side loot effects (pure)

## Dungeon Ticket drop chance for a kill: base x (1 + item quantity) x (1 + atlas ticket bonus).
static func ticket_chance(base: float, quantity: float, afx: Dictionary) -> float:
	return base * (1.0 + quantity / 100.0) * (1.0 + float(afx.get("tq", 0.0)) / 100.0)


## Extra drops from atlas passives for one kill: {"loot_rolls": n, "orbs": [ids]}.
##  - region boost: reg% chance of one extra loot roll (non-boss)
##  - boss loot: boss% chance of one extra boss loot roll (+ one more above 100%)
##  - currency: cur% x 5% chance of a bonus crafting orb per kill
static func roll_extras(afx: Dictionary, boss: bool, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"loot_rolls": 0, "orbs": []}
	if afx.is_empty():
		return out
	var reg := float(afx.get("reg", 0.0))
	if not boss and reg > 0.0 and rng.randf() < reg / 100.0:
		out["loot_rolls"] += 1
	var bl := float(afx.get("boss", 0.0))
	if boss and bl > 0.0:
		out["loot_rolls"] += int(bl / 100.0) + (1 if rng.randf() < fmod(bl, 100.0) / 100.0 else 0)
	var cur := float(afx.get("cur", 0.0))
	if cur > 0.0 and rng.randf() < 0.05 * cur / 100.0:
		var pool := ["orb_transmute", "orb_alteration", "orb_regal", "orb_chaos", "orb_exalt", "orb_scour", "orb_chisel"]
		out["orbs"].append(pool[rng.randi() % pool.size()])
	return out


static func _fx_short(fx: Dictionary) -> String:
	var parts: Array = []
	for k in fx:
		if float(fx[k]) != 0.0:
			parts.append("%s %d" % [k, roundi(float(fx[k]))])
	return "{" + ", ".join(parts) + "}"
