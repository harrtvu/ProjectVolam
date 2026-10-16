class_name Talents
## The PASSIVE WEB: one shared graph of ~200 passive nodes for every class (Path of Exile style).
##
## * The five class START nodes sit on the corners of the Ngu Hanh pentagon, in generating order
##   (Wood -> Fire -> Earth -> Metal -> Water -> Wood). Your own class start is allocated for free.
## * You may only allocate a node ADJACENT to one you already own (the web must stay connected).
## * Node types: small (minor stat), notable (named, bigger / skill modifier), keystone (build-defining:
##   the old class capstones near each start, and five generic trade-off keystones in the centre),
##   start (class start; other classes' starts are ordinary 1-point nodes you can path through).
## * Around each start are two class clusters (the class's specialisations) generated from TREES below:
##   chains of small nodes (one per former rank) -> notables -> a class keystone ~10 points out.
##   The pentagon edges are "ring" paths with farming notables between neighbouring elements, spokes
##   lead inward to a hub ring with the centre keystones.
## * 1 point per level from level 2 (points = level - 1, so existing characters get them retroactively).
##   Refund a single node for gold (only if the rest stays connected) or reset everything for gold.
## * Nodes only produce generic modifiers ({stat_key: value}); Stats.gather() merges them with gear
##   affixes, so combat/loot code never needs to know where a bonus came from.
## Client and server both use these pure functions, so the UI shows exactly what the server applies.
##
## Effect keys (values in "human" units):
##   hp_pct mp_pct atk_pct speed_pct mp_regen_pct heal_pct cost_pct crit crit_dmg dmg_taken_pct
##   reflect vs_slowed -> percent ; def_flat mp_on_hit -> flat
##   item_rarity item_quantity gold_find life_leech mana_leech attack_speed cast_speed dmg_vs:<element>
##   dot_poison dot_burn (percent dps)   dur_poison (+s)   slow_pct (+% strength)  dur_slow (+s)
##   dmg:<skill> cd:<skill> radius:<skill> range:<skill> heal:<skill> shield:<skill> -> percent
##   stun:<skill> dur:<skill> (+s)   count:<skill> pulses:<skill> (+n)
##   flag:<name> -> keystone behaviour (see player.gd / skill_caster.gd / monster.gd)

const RESPEC_BASE := 20          # full reset: 20 + 10 x level gold
const RESPEC_PER_LEVEL := 10
const REFUND_BASE := 5           # refunding one node: 5 + 2 x level gold
const REFUND_PER_LEVEL := 2

## Source data for the class clusters of the web. class -> [cluster, cluster];
## cluster = {name, desc, talents: [{id, name, tier, ranks, fx: [[key, value], ...], desc}]}.
## tier 1 -> a chain of `ranks` small nodes (fx per node); tier 2/3 -> one notable (fx x ranks);
## tier 4 -> the class keystone at the end of the cluster. In desc, {0} {1} ... are fx values.
const TREES := {
	"metal": [
		{"name": "Swordsman", "desc": "Sustained melee and the whirling blade.", "talents": [
			{"id": "m_honed", "name": "Honed Edge", "tier": 1, "ranks": 3, "fx": [["atk_pct", 4]], "desc": "+{0}% attack"},
			{"id": "m_steel", "name": "Steel Body", "tier": 1, "ranks": 3, "fx": [["hp_pct", 5]], "desc": "+{0}% max HP"},
			{"id": "m_cyclone", "name": "Cyclone", "tier": 2, "ranks": 3, "fx": [["dmg:whirl", 15], ["radius:whirl", 8]], "desc": "Whirling Blade: +{0}% damage, +{1}% radius"},
			{"id": "m_rhythm", "name": "Battle Rhythm", "tier": 2, "ranks": 2, "fx": [["mp_on_hit", 2]], "desc": "Basic attack hits restore {0} mana"},
			{"id": "m_bloodthirst", "name": "Bloodthirst", "tier": 2, "ranks": 2, "fx": [["life_leech", 1.5]], "desc": "{0}% of damage dealt is leeched as life"},
			{"id": "m_relentless", "name": "Relentless", "tier": 3, "ranks": 2, "fx": [["cd:whirl", 20]], "desc": "Whirling Blade cooldown -{0}%"},
			{"id": "m_bladestorm", "name": "Blade Storm", "tier": 4, "ranks": 1, "fx": [["flag:bladestorm", 1]], "desc": "CAPSTONE: Whirling Blade spins a second time 0.3 s later for 60% damage"},
		]},
		{"name": "Assassin", "desc": "Critical strikes, mobility and executions.", "talents": [
			{"id": "m_keen", "name": "Keen Eye", "tier": 1, "ranks": 3, "fx": [["crit", 3]], "desc": "+{0}% critical chance"},
			{"id": "m_fleet", "name": "Fleet Foot", "tier": 1, "ranks": 3, "fx": [["speed_pct", 4]], "desc": "+{0}% movement speed"},
			{"id": "m_plunder", "name": "Plunderer", "tier": 1, "ranks": 3, "fx": [["gold_find", 10], ["item_rarity", 6]], "desc": "+{0}% gold found, +{1}% item rarity"},
			{"id": "m_lethal", "name": "Lethal Precision", "tier": 2, "ranks": 3, "fx": [["crit_dmg", 15]], "desc": "+{0}% critical damage"},
			{"id": "m_shadow", "name": "Shadowstep", "tier": 2, "ranks": 2, "fx": [["cd:pierce", 15], ["range:pierce", 20]], "desc": "Piercing Strike: cooldown -{0}%, dash range +{1}%"},
			{"id": "m_mind", "name": "Focused Mind", "tier": 3, "ranks": 2, "fx": [["dur:focus", 2]], "desc": "Blade Focus lasts +{0} s"},
			{"id": "m_deathmark", "name": "Death Mark", "tier": 4, "ranks": 1, "fx": [["flag:deathmark", 1], ["count:cuts", 3]], "desc": "CAPSTONE: Thousand Cuts strikes {1} more times, and ALL your hits on enemies below 30% HP deal double damage"},
		]},
	],
	"wood": [
		{"name": "Toxin", "desc": "Deadlier, longer, spreading poison.", "talents": [
			{"id": "w_virulence", "name": "Virulence", "tier": 1, "ranks": 3, "fx": [["dot_poison", 10]], "desc": "Poison deals +{0}% damage"},
			{"id": "w_mind", "name": "Toxic Mind", "tier": 1, "ranks": 3, "fx": [["mp_pct", 5]], "desc": "+{0}% max mana"},
			{"id": "w_barbed", "name": "Barbed Thorn", "tier": 2, "ranks": 3, "fx": [["dmg:thorn", 15]], "desc": "Poison Thorn deals +{0}% damage"},
			{"id": "w_linger", "name": "Lingering Venom", "tier": 2, "ranks": 2, "fx": [["dur_poison", 1.5]], "desc": "Your poisons last +{0} s"},
			{"id": "w_blight", "name": "Blight the Blade", "tier": 2, "ranks": 2, "fx": [["dmg_vs:metal", 12]], "desc": "+{0}% damage vs Metal monsters (your counter element)"},
			{"id": "w_spread", "name": "Spreading Bloom", "tier": 3, "ranks": 2, "fx": [["radius:bloom", 15], ["cd:bloom", 10]], "desc": "Plague Bloom: +{0}% radius, cooldown -{1}%"},
			{"id": "w_pandemic", "name": "Pandemic", "tier": 4, "ranks": 1, "fx": [["flag:pandemic", 1]], "desc": "CAPSTONE: when a poisoned enemy dies, its poison jumps to every enemy within 100 px"},
		]},
		{"name": "Grove", "desc": "Bark, roots and regrowth: the druid who never falls.", "talents": [
			{"id": "w_bark", "name": "Bark Skin", "tier": 1, "ranks": 3, "fx": [["def_flat", 1], ["hp_pct", 4]], "desc": "+{0} defense, +{1}% max HP"},
			{"id": "w_sap", "name": "Sap Flow", "tier": 1, "ranks": 3, "fx": [["mp_regen_pct", 10]], "desc": "+{0}% mana regeneration"},
			{"id": "w_forager", "name": "Forager", "tier": 1, "ranks": 3, "fx": [["item_quantity", 5], ["gold_find", 5]], "desc": "+{0}% item quantity, +{1}% gold found"},
			{"id": "w_roots", "name": "Deep Roots", "tier": 2, "ranks": 3, "fx": [["stun:roots", 0.3], ["radius:roots", 10]], "desc": "Entangling Roots: +{0} s root, +{1}% radius"},
			{"id": "w_verdant", "name": "Verdant Growth", "tier": 2, "ranks": 2, "fx": [["heal:regrowth", 25]], "desc": "Regrowth heals +{0}%"},
			{"id": "w_lifebloom", "name": "Lifebloom", "tier": 3, "ranks": 2, "fx": [["cd:regrowth", 15]], "desc": "Regrowth cooldown -{0}%"},
			{"id": "w_heart", "name": "Heart of the Forest", "tier": 4, "ranks": 1, "fx": [["flag:grove_heart", 1]], "desc": "CAPSTONE: Regrowth also heals allies within 150 px, and while it is active you take 20% less damage"},
		]},
	],
	"water": [
		{"name": "Frost", "desc": "Slows, freezes and shatters.", "talents": [
			{"id": "a_biting", "name": "Biting Cold", "tier": 1, "ranks": 3, "fx": [["dmg:ice_shard", 12]], "desc": "Ice Shard deals +{0}% damage"},
			{"id": "a_glacial", "name": "Glacial Mind", "tier": 1, "ranks": 3, "fx": [["mp_pct", 5]], "desc": "+{0}% max mana"},
			{"id": "a_permafrost", "name": "Permafrost", "tier": 2, "ranks": 3, "fx": [["slow_pct", 8], ["dur_slow", 0.5]], "desc": "Your slows are {0}% stronger and last +{1} s"},
			{"id": "a_deepfreeze", "name": "Deep Freeze", "tier": 2, "ranks": 2, "fx": [["stun:nova", 0.4], ["radius:nova", 10]], "desc": "Frost Nova: +{0} s freeze, +{1}% radius"},
			{"id": "a_siphon", "name": "Frost Siphon", "tier": 2, "ranks": 2, "fx": [["mana_leech", 1.5]], "desc": "{0}% of damage dealt is leeched as mana"},
			{"id": "a_shatter", "name": "Shatter", "tier": 3, "ranks": 2, "fx": [["vs_slowed", 20]], "desc": "+{0}% damage to slowed or frozen enemies"},
			{"id": "a_zero", "name": "Absolute Zero", "tier": 4, "ranks": 1, "fx": [["flag:shard_pierce", 1], ["cd:ice_shard", 50]], "desc": "CAPSTONE: Ice Shard pierces through every enemy in its path and its cooldown is halved"},
		]},
		{"name": "Tide", "desc": "Healing, protection and crashing waves.", "talents": [
			{"id": "a_grace", "name": "Flowing Grace", "tier": 1, "ranks": 3, "fx": [["heal_pct", 10]], "desc": "Your healing is +{0}% stronger"},
			{"id": "a_body", "name": "Tidal Body", "tier": 1, "ranks": 3, "fx": [["hp_pct", 5]], "desc": "+{0}% max HP"},
			{"id": "a_luck", "name": "Tidecaller's Luck", "tier": 1, "ranks": 3, "fx": [["item_rarity", 8]], "desc": "+{0}% item rarity"},
			{"id": "a_spring", "name": "Spring Rain", "tier": 2, "ranks": 3, "fx": [["radius:rain", 10], ["cd:rain", 8]], "desc": "Healing Rain: +{0}% radius, cooldown -{1}%"},
			{"id": "a_undertow", "name": "Undertow", "tier": 2, "ranks": 2, "fx": [["dmg:wave", 20]], "desc": "Tidal Wave deals +{0}% damage"},
			{"id": "a_clarity", "name": "Clarity", "tier": 3, "ranks": 2, "fx": [["cost_pct", 8]], "desc": "All skills cost {0}% less mana"},
			{"id": "a_well", "name": "Wellspring", "tier": 4, "ranks": 1, "fx": [["flag:wellspring", 1]], "desc": "CAPSTONE: Healing Rain also shields everyone it heals for 15% of their max HP (6 s) and restores 10% of their mana"},
		]},
	],
	"fire": [
		{"name": "Inferno", "desc": "Bigger fires, more fires, everywhere.", "talents": [
			{"id": "f_kindling", "name": "Kindling", "tier": 1, "ranks": 3, "fx": [["atk_pct", 4]], "desc": "+{0}% attack"},
			{"id": "f_wildfire", "name": "Wildfire", "tier": 1, "ranks": 3, "fx": [["dot_burn", 12]], "desc": "Burns deal +{0}% damage"},
			{"id": "f_conflag", "name": "Conflagration", "tier": 2, "ranks": 3, "fx": [["radius:burst", 12], ["dmg:burst", 10]], "desc": "Flame Burst: +{0}% radius, +{1}% damage"},
			{"id": "f_storm", "name": "Firestorm", "tier": 2, "ranks": 2, "fx": [["count:inferno", 2]], "desc": "Inferno fires {0} more bolts"},
			{"id": "f_quicken", "name": "Quickening Flames", "tier": 2, "ranks": 2, "fx": [["cast_speed", 6]], "desc": "+{0}% cast speed (all skill cooldowns recover faster)"},
			{"id": "f_cataclysm", "name": "Cataclysm", "tier": 3, "ranks": 2, "fx": [["radius:meteor", 15], ["cd:meteor", 10]], "desc": "Meteor: +{0}% radius, cooldown -{1}%"},
			{"id": "f_shower", "name": "Meteor Shower", "tier": 4, "ranks": 1, "fx": [["flag:meteor_shower", 1]], "desc": "CAPSTONE: each Meteor is followed by 2 smaller meteors (60% damage) on other enemies nearby"},
		]},
		{"name": "Ember", "desc": "Single-target burst and a fire that refuses to die.", "talents": [
			{"id": "f_focus", "name": "Ember Focus", "tier": 1, "ranks": 3, "fx": [["crit", 3]], "desc": "+{0}% critical chance"},
			{"id": "f_font", "name": "Mana Font", "tier": 1, "ranks": 3, "fx": [["mp_pct", 5]], "desc": "+{0}% max mana"},
			{"id": "f_greed", "name": "Ember Greed", "tier": 1, "ranks": 3, "fx": [["gold_find", 12]], "desc": "+{0}% gold found"},
			{"id": "f_pyro", "name": "Pyroblast", "tier": 2, "ranks": 3, "fx": [["dmg:fireball", 15]], "desc": "Fireball deals +{0}% damage"},
			{"id": "f_ignite", "name": "Ignition", "tier": 2, "ranks": 2, "fx": [["cd:fireball", 15]], "desc": "Fireball cooldown -{0}%"},
			{"id": "f_combust", "name": "Combustion", "tier": 3, "ranks": 2, "fx": [["crit_dmg", 25]], "desc": "+{0}% critical damage"},
			{"id": "f_phoenix", "name": "Phoenix Heart", "tier": 4, "ranks": 1, "fx": [["flag:phoenix", 1]], "desc": "CAPSTONE: once every 60 s, a killing blow instead leaves you at 30% HP and you explode in a Flame Burst"},
		]},
	],
	"earth": [
		{"name": "Bulwark", "desc": "The wall that the party hides behind.", "talents": [
			{"id": "e_granite", "name": "Granite", "tier": 1, "ranks": 3, "fx": [["def_flat", 2]], "desc": "+{0} defense"},
			{"id": "e_heart", "name": "Mountain Heart", "tier": 1, "ranks": 3, "fx": [["hp_pct", 6]], "desc": "+{0}% max HP"},
			{"id": "e_prospect", "name": "Prospector", "tier": 1, "ranks": 3, "fx": [["item_quantity", 5], ["item_rarity", 4]], "desc": "+{0}% item quantity, +{1}% item rarity"},
			{"id": "e_shield", "name": "Reinforced Stone", "tier": 2, "ranks": 3, "fx": [["shield:stoneskin", 15]], "desc": "Stone Skin absorbs +{0}% more"},
			{"id": "e_firm", "name": "Stand Firm", "tier": 2, "ranks": 2, "fx": [["cd:taunt", 15], ["radius:taunt", 10]], "desc": "Mountain's Challenge: cooldown -{0}%, radius +{1}%"},
			{"id": "e_thorns", "name": "Thorns of Stone", "tier": 3, "ranks": 2, "fx": [["reflect", 15]], "desc": "Reflect {0}% of melee damage taken back at the attacker"},
			{"id": "e_unbreak", "name": "Unbreakable", "tier": 4, "ranks": 1, "fx": [["flag:unbreakable", 1], ["dmg_taken_pct", 15]], "desc": "CAPSTONE: take {1}% less damage; when Stone Skin breaks or ends it erupts, stunning enemies within 110 px for 1.5 s"},
		]},
		{"name": "Quake", "desc": "Shake the ground until nothing stands.", "talents": [
			{"id": "e_hands", "name": "Heavy Hands", "tier": 1, "ranks": 3, "fx": [["atk_pct", 5]], "desc": "+{0}% attack"},
			{"id": "e_tremor", "name": "Tremor", "tier": 1, "ranks": 3, "fx": [["dmg:slam", 12]], "desc": "Ground Slam deals +{0}% damage"},
			{"id": "e_reach", "name": "Seismic Reach", "tier": 2, "ranks": 3, "fx": [["radius:slam", 8], ["radius:quake", 8]], "desc": "Ground Slam +{0}% and Earthquake +{1}% radius"},
			{"id": "e_concuss", "name": "Concussion", "tier": 2, "ranks": 2, "fx": [["stun:slam", 0.3]], "desc": "Ground Slam stuns +{0} s longer"},
			{"id": "e_rhythm", "name": "Rhythm of Stone", "tier": 2, "ranks": 2, "fx": [["attack_speed", 8], ["dmg_vs:wood", 10]], "desc": "+{0}% attack speed, +{1}% damage vs Wood monsters (your counter element)"},
			{"id": "e_rolling", "name": "Rolling Thunder", "tier": 3, "ranks": 2, "fx": [["pulses:quake", 1]], "desc": "Earthquake has {0} more tremors"},
			{"id": "e_tectonic", "name": "Tectonic Fury", "tier": 4, "ranks": 1, "fx": [["flag:tectonic", 1], ["cd:slam", 50]], "desc": "CAPSTONE: every Earthquake tremor stuns for 0.6 s, and Ground Slam's cooldown is halved"},
		]},
	],
}

## ---------------------------------------------------------------- web generation

const RING_ORDER := ["wood", "fire", "earth", "metal", "water"]   # generating cycle, clockwise from the top
const START_R := 430.0
const STEP := 36.0
const START_FX := {
	"metal": [["crit", 2]], "wood": [["hp_pct", 3], ["dot_poison", 5]], "water": [["mp_pct", 5]],
	"fire": [["atk_pct", 3]], "earth": [["def_flat", 2]],
}
## farming notables on the pentagon edge between two neighbouring elements (key = "a-b" in RING_ORDER)
const RING_NOTABLES := {
	"wood-fire": ["Kindled Harvest", [["item_quantity", 10], ["gold_find", 5]]],
	"fire-earth": ["Ash and Ore", [["gold_find", 15], ["item_rarity", 6]]],
	"earth-metal": ["Forgeborn", [["attack_speed", 8], ["atk_pct", 4]]],
	"metal-water": ["Quicksilver", [["cast_speed", 8], ["speed_pct", 5]]],
	"water-wood": ["Life Spring", [["life_leech", 2], ["mp_regen_pct", 10]]],
}
const RING_SMALLS := [[["atk_pct", 2]], [["item_rarity", 4]], [["hp_pct", 3]], [["gold_find", 5]]]
## centre keystones: big trade-offs (sit between hub nodes i and i+1)
const KEYSTONES := [
	["k_glass", "Glass Cannon", [["atk_pct", 30], ["hp_pct", -25]]],
	["k_greed", "Treasure Hunter's Oath", [["item_quantity", 30], ["item_rarity", 30], ["gold_find", 40], ["atk_pct", -20]]],
	["k_blood", "Blood Pact", [["life_leech", 5], ["mp_regen_pct", -50]]],
	["k_stone", "Unyielding", [["dmg_taken_pct", 20], ["speed_pct", -15], ["attack_speed", -15]]],
	["k_wind", "Wind Walker", [["speed_pct", 20], ["attack_speed", 15], ["cast_speed", 15], ["hp_pct", -15]]],
]
## what "overcomes" each element (spokes give damage vs the element you're weak to)
const COUNTER := {"metal": "fire", "wood": "metal", "water": "earth", "fire": "water", "earth": "wood"}

static var NODES := {}       # id -> {id, name, type, cls, pos, fx, desc, links}
static var _old_ids := {}    # former talent-tree id -> true (for migrating old saves)


static func _node(id: String, name: String, type: String, cls: String, pos: Vector2, fx: Array, desc := "") -> void:
	NODES[id] = {"id": id, "name": name, "type": type, "cls": cls, "pos": pos, "fx": fx, "desc": desc, "links": []}


static func _link(a: String, b: String) -> void:
	if not NODES[a]["links"].has(b):
		NODES[a]["links"].append(b)
		NODES[b]["links"].append(a)


static func _fmt_desc(t: Dictionary, mult: int) -> String:
	var d: String = t["desc"]
	for i in t["fx"].size():
		var v: float = float(t["fx"][i][1]) * mult
		d = d.replace("{%d}" % i, ("%d" % v) if is_equal_approx(v, roundf(v)) else ("%.1f" % v))
	return d


static func _scaled(fx: Array, mult: int) -> Array:
	var out: Array = []
	for e in fx:
		out.append([e[0], float(e[1]) * mult])
	return out


static func _build() -> void:
	if not NODES.is_empty():
		return
	var roman := ["I", "II", "III"]
	for i in RING_ORDER.size():
		var cls: String = RING_ORDER[i]
		var ang := -PI / 2.0 + TAU * i / 5.0
		var out := Vector2.from_angle(ang)
		var sid := "start_" + cls
		var S := out * START_R
		_node(sid, "%s start" % Classes.ELEMENT_INFO[cls]["name"], "start", cls, S, START_FX[cls])
		# two class clusters, fanning outward at -/+ 30 degrees
		for b in 2:
			var br: Dictionary = TREES[cls][b]
			var side := -1.0 if b == 0 else 1.0
			var d := out.rotated(side * deg_to_rad(30.0))
			var t1: Array = []
			var t2: Array = []
			var t3: Array = []
			var cap := {}
			for t in br["talents"]:
				_old_ids[t["id"]] = true
				match int(t["tier"]):
					1: t1.append(t)
					2: t2.append(t)
					3: t3.append(t)
					4: cap = t
			# main path: chain(t1[0]) -> notable t2[0] -> chain(t1[1]) -> notable t2[1] -> notable t3[0] -> keystone
			var path: Array = []
			var seq: Array = []
			seq.append(["chain", t1[0]]); seq.append(["notable", t2[0]])
			seq.append(["chain", t1[1]]); seq.append(["notable", t2[1]])
			for t in t3:
				seq.append(["notable", t])
			seq.append(["keystone", cap])
			var prev := sid
			var j := 0
			var n1_id := ""
			for e in seq:
				var t: Dictionary = e[1]
				if e[0] == "chain":
					for r in int(t["ranks"]):
						j += 1
						var nid := "%s_%d" % [t["id"], r + 1]
						_node(nid, "%s %s" % [t["name"], roman[r]], "small", cls, S + d * STEP * j * 1.15, t["fx"], _fmt_desc(t, 1))
						_link(prev, nid)
						prev = nid
				else:
					j += 1
					var mult := int(t["ranks"])
					var kind: String = e[0]
					var desc := _fmt_desc(t, mult).replace("CAPSTONE: ", "")
					if kind == "keystone":
						desc += "  (%s class keystone)" % Classes.ELEMENT_INFO[cls]["name"]
					elif t["fx"][0][0].contains(":") and not t["fx"][0][0].begins_with("dmg_vs"):
						desc += "  (%s skill)" % Classes.ELEMENT_INFO[cls]["name"]
					_node(t["id"], t["name"], kind, cls, S + d * STEP * j * 1.15, _scaled(t["fx"], mult), desc)
					_link(prev, t["id"])
					prev = t["id"]
					if n1_id == "":
						n1_id = t["id"]
			# side path off the first notable: chain(t1[2]) -> notable t2[2]
			if t1.size() > 2 or t2.size() > 2:
				var sd := d.rotated(side * deg_to_rad(55.0))
				var base: Vector2 = NODES[n1_id]["pos"]
				var sp := n1_id
				var k := 0
				if t1.size() > 2:
					var t: Dictionary = t1[2]
					for r in int(t["ranks"]):
						k += 1
						var nid := "%s_%d" % [t["id"], r + 1]
						_node(nid, "%s %s" % [t["name"], roman[r]], "small", cls, base + sd * STEP * k, t["fx"], _fmt_desc(t, 1))
						_link(sp, nid)
						sp = nid
				if t2.size() > 2:
					var t: Dictionary = t2[2]
					k += 1
					_node(t["id"], t["name"], "notable", cls, base + sd * STEP * k, _scaled(t["fx"], int(t["ranks"])), _fmt_desc(t, int(t["ranks"])))
					_link(sp, t["id"])
		# spoke inward: 2 smalls + a "bane" notable, then the hub node
		var ce: String = COUNTER[cls]
		var cname: String = Classes.ELEMENT_INFO[ce]["name"]
		var prev2 := sid
		for k in 2:
			var nid := "spoke_%s_%d" % [cls, k + 1]
			_node(nid, "%s Ward %s" % [cname, roman[k]], "small", "", out * (START_R - 70.0 * (k + 1)), [["dmg_vs:" + ce, 6]], "")
			_link(prev2, nid)
			prev2 = nid
		var bane := "bane_" + ce
		_node(bane, "Bane of %s" % cname, "notable", "", out * (START_R - 210.0), [["dmg_vs:" + ce, 15], ["item_rarity", 5]], "")
		_link(prev2, bane)
		var hub := "hub_" + cls
		_node(hub, "Heart of the Web", "small", "", out * 150.0, [["hp_pct", 2], ["mp_pct", 2]], "")
		_link(bane, hub)
	# hub ring + centre keystones, pentagon edges
	for i in 5:
		var a: String = RING_ORDER[i]
		var b: String = RING_ORDER[(i + 1) % 5]
		_link("hub_" + a, "hub_" + b)
		var ks: Array = KEYSTONES[i]
		var kang := -PI / 2.0 + TAU * (i + 0.5) / 5.0
		_node(ks[0], ks[1], "keystone", "", Vector2.from_angle(kang) * 250.0, ks[2], "")
		_link(ks[0], "hub_" + a)
		_link(ks[0], "hub_" + b)
		var A: Vector2 = NODES["start_" + a]["pos"]
		var B: Vector2 = NODES["start_" + b]["pos"]
		var prev := "start_" + a
		for k in 5:
			var p := A.lerp(B, float(k + 1) / 6.0) * 0.93
			var nid := "ring_%s_%s_%d" % [a, b, k + 1]
			if k == 2:
				var rn: Array = RING_NOTABLES["%s-%s" % [a, b]]
				_node(nid, rn[0], "notable", "", p, rn[1], "")
			else:
				var fx: Array = RING_SMALLS[(k if k < 2 else k - 1) % RING_SMALLS.size()]
				_node(nid, "Wanderer's Path", "small", "", p, fx, "")
			_link(prev, nid)
			prev = nid
		_link(prev, "start_" + b)
	# default descriptions from fx
	for id in NODES:
		if NODES[id]["desc"] == "":
			NODES[id]["desc"] = ", ".join(Stats.describe(_fx_dict(NODES[id]["fx"])))


static func _fx_dict(fx: Array) -> Dictionary:
	var m := {}
	for e in fx:
		m[e[0]] = float(m.get(e[0], 0.0)) + float(e[1])
	return m


## ---------------------------------------------------------------- rules

static func node(id: String) -> Dictionary:
	_build()
	return NODES.get(id, {})


static func all_nodes() -> Dictionary:
	_build()
	return NODES


static func start_of(cls: String) -> String:
	return "start_" + cls


static func is_old_id(id: String) -> bool:
	_build()
	return _old_ids.has(id) and not NODES.has(id)


static func points_total(level: int) -> int:
	return maxi(0, level - 1)


static func points_spent(talents: Dictionary) -> int:
	return talents.size()   # the class start is implicit and free


static func respec_cost(level: int) -> int:
	return RESPEC_BASE + RESPEC_PER_LEVEL * level


static func refund_cost(level: int) -> int:
	return REFUND_BASE + REFUND_PER_LEVEL * level


static func is_allocated(cls: String, talents: Dictionary, id: String) -> bool:
	return id == start_of(cls) or talents.has(id)


static func is_adjacent(cls: String, talents: Dictionary, id: String) -> bool:
	for l in node(id).get("links", []):
		if is_allocated(cls, talents, l):
			return true
	return false


## Why a node can't be allocated right now ("" = it can).
static func can_learn(cls: String, level: int, talents: Dictionary, id: String) -> String:
	var n := node(id)
	if n.is_empty():
		return "there is no passive node '%s'" % id
	if is_allocated(cls, talents, id):
		return "%s is already allocated" % n["name"]
	if points_spent(talents) >= points_total(level):
		return "no passive points left"
	if not is_adjacent(cls, talents, id):
		return "%s is not connected to your allocated nodes" % n["name"]
	return ""


## Allocated nodes still reachable from the class start if `without` is removed.
static func _reachable(cls: String, talents: Dictionary, without: String) -> Dictionary:
	var seen := {start_of(cls): true}
	var queue: Array = [start_of(cls)]
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for l in node(cur).get("links", []):
			if l != without and talents.has(l) and not seen.has(l):
				seen[l] = true
				queue.append(l)
	return seen


## Why a node can't be refunded ("" = it can). Gold is checked by the server.
static func can_refund(cls: String, talents: Dictionary, id: String) -> String:
	var n := node(id)
	if n.is_empty():
		return "there is no passive node '%s'" % id
	if id == start_of(cls):
		return "your class start can't be refunded"
	if not talents.has(id):
		return "%s is not allocated" % n["name"]
	var r := _reachable(cls, talents, id)
	for k in talents:
		if k != id and not r.has(k):
			return "refunding %s would disconnect %s" % [n["name"], node(k)["name"]]
	return ""


## Cleans a saved allocation: unknown ids dropped; anything disconnected or over budget -> full refund.
static func sanitize(cls: String, level: int, talents: Dictionary) -> Dictionary:
	var out := {}
	for k in talents:
		if not node(str(k)).is_empty() and str(k) != start_of(cls):
			out[str(k)] = 1
	if out.size() > points_total(level):
		return {}
	var r := _reachable(cls, out, "")
	for k in out:
		if not r.has(k):
			return {}
	return out


## Shortest path of unallocated nodes from the current allocation to `goal` (for bots / tests).
static func path_to(cls: String, talents: Dictionary, goal: String) -> Array:
	var prev := {}
	var queue: Array = []
	for id in talents.keys() + [start_of(cls)]:
		prev[id] = ""
		queue.append(id)
	var qi := 0
	while qi < queue.size():
		var cur: String = queue[qi]
		qi += 1
		if cur == goal:
			break
		for l in node(cur).get("links", []):
			if not prev.has(l):
				prev[l] = cur
				queue.append(l)
	if not prev.has(goal):
		return []
	var path: Array = []
	var c := goal
	while c != "" and not is_allocated(cls, talents, c):
		path.push_front(c)
		c = prev[c]
	return path


## Sum of all allocated node effects (own class start included): key -> total value.
static func mods(cls: String, talents: Dictionary) -> Dictionary:
	var m := {}
	var ids: Array = talents.keys()
	if Classes.ELEMENTS.has(cls):
		ids.append(start_of(cls))
	for id in ids:
		var n := node(str(id))
		if n.is_empty():
			continue
		for e in n["fx"]:
			m[e[0]] = float(m.get(e[0], 0.0)) + float(e[1])
	return m


static func _g(m: Dictionary, k: String) -> float:
	return float(m.get(k, 0.0))


## A skill definition with talents only (no gear) applied.
static func skill_def(cls: String, talents: Dictionary, sid: String) -> Dictionary:
	return skill_def_m(mods(cls, talents), sid)


## A skill definition with an aggregated modifier dict (Stats.gather) applied.
## Used by the server for casting AND by the UI, so both always agree.
static func skill_def_m(m: Dictionary, sid: String) -> Dictionary:
	var sk: Dictionary = Classes.SKILLS[sid].duplicate(true)
	if m.is_empty():
		return sk
	if sk.has("mult"):
		sk["mult"] = float(sk["mult"]) * (1.0 + _g(m, "dmg:" + sid) / 100.0)
	sk["cd"] = float(sk["cd"]) * maxf(0.2, 1.0 - _g(m, "cd:" + sid) / 100.0) / (1.0 + _g(m, "cast_speed") / 100.0)
	sk["cost"] = roundi(float(sk["cost"]) * (1.0 - _g(m, "cost_pct") / 100.0))
	for key in ["radius", "range"]:
		if sk.has(key):
			sk[key] = float(sk[key]) * (1.0 + _g(m, key + ":" + sid) / 100.0)
	if sk.has("stun"):
		sk["stun"] = float(sk["stun"]) + _g(m, "stun:" + sid)
	if sk.has("duration"):
		sk["duration"] = float(sk["duration"]) + _g(m, "dur:" + sid)
	if sk.has("count"):
		sk["count"] = int(sk["count"]) + int(_g(m, "count:" + sid))
	if sk.has("hits"):
		sk["hits"] = int(sk["hits"]) + int(_g(m, "count:" + sid))
	if sk.has("pulses"):
		sk["pulses"] = int(sk["pulses"]) + int(_g(m, "pulses:" + sid))
	if sk.has("amount"):
		sk["amount"] = float(sk["amount"]) * (1.0 + _g(m, "shield:" + sid) / 100.0)
	var heal_mult := (1.0 + _g(m, "heal_pct") / 100.0) * (1.0 + _g(m, "heal:" + sid) / 100.0)
	for key in ["heal", "instant", "per_sec"]:
		if sk.has(key):
			sk[key] = float(sk[key]) * heal_mult
	if sk.has("poison"):
		sk["poison"] = [float(sk["poison"][0]) * (1.0 + _g(m, "dot_poison") / 100.0), float(sk["poison"][1]) + _g(m, "dur_poison")]
	if sk.has("burn"):
		sk["burn"] = [float(sk["burn"][0]) * (1.0 + _g(m, "dot_burn") / 100.0), float(sk["burn"][1])]
	if sk.has("slow"):
		sk["slow"] = [minf(0.85, float(sk["slow"][0]) * (1.0 + _g(m, "slow_pct") / 100.0)), float(sk["slow"][1]) + _g(m, "dur_slow")]
	if sid == "ice_shard" and _g(m, "flag:shard_pierce") > 0.0:
		sk["pierce"] = true
	if sid == "quake" and _g(m, "flag:tectonic") > 0.0:
		sk["stun"] = 0.6
	if sid == "cuts" and _g(m, "flag:deathmark") > 0.0:
		sk["execute"] = true
	return sk
