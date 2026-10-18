class_name Classes
## The five elemental classes (Wu Xing / Ngũ Hành) and their skills, plus the
## element cycle used for damage multipliers.
##
## Overcoming (khắc) cycle: Metal > Wood > Earth > Water > Fire > Metal
##   attacker overcomes defender -> x1.25 damage, defender overcomes attacker -> x0.80
## Generating (sinh) cycle: Wood -> Fire -> Earth -> Metal -> Water -> Wood
##   healing from the element that generates you is +20%.

const ELEMENTS := ["metal", "wood", "water", "fire", "earth"]
const OVERCOMES := {"metal": "wood", "wood": "earth", "earth": "water", "water": "fire", "fire": "metal"}
const GENERATES := {"wood": "fire", "fire": "earth", "earth": "metal", "metal": "water", "water": "wood"}
const STRONG := 1.25
const WEAK := 0.8

const ELEMENT_INFO := {
	"metal": {"name": "Metal", "viet": "Kim", "color": Color(0.95, 0.85, 0.45)},
	"wood": {"name": "Wood", "viet": "Mộc", "color": Color(0.35, 0.82, 0.35)},
	"water": {"name": "Water", "viet": "Thủy", "color": Color(0.35, 0.65, 1.0)},
	"fire": {"name": "Fire", "viet": "Hỏa", "color": Color(1.0, 0.42, 0.2)},
	"earth": {"name": "Earth", "viet": "Thổ", "color": Color(0.8, 0.6, 0.32)},
}

## Stats: value = base + per_level * (level - 1)
const DB := {
	"metal": {"name": "Blade Master", "element": "metal", "role": "Melee DPS",
		"desc": "Kim. A swordsman of tempered steel: the highest melee damage and critical strikes. Fast, but needs to stay close.",
		"hp": [32, 7.0], "mp": [30, 3.0], "atk": [3, 0.9], "def": [1, 0.3], "speed": 168, "crit": [0.08, 0.003],
		"basic": "melee", "start_gear": {"weapon": "iron_sword"}, "start_items": {"health_potion": 2},
		"skills": ["whirl", "pierce", "focus", "cuts"]},
	"wood": {"name": "Venom Druid", "element": "wood", "role": "Damage over time / self-heal",
		"desc": "Mộc. Wields thorns, roots and poison. Enemies wither over time while the druid regrows its own wounds.",
		"hp": [32, 7.0], "mp": [40, 4.0], "atk": [3, 1.25], "def": [1, 0.35], "speed": 160, "crit": [0.06, 0.002],
		"basic": "melee", "start_gear": {"weapon": "apprentice_staff"}, "start_items": {"health_potion": 2},
		"skills": ["thorn", "regrowth", "roots", "bloom"]},
	"water": {"name": "Frost Sage", "element": "water", "role": "Ranged control / support healer",
		"desc": "Thủy. Ice shards slow, frost novas freeze, and healing rain mends the sage and nearby allies.",
		"hp": [30, 6.5], "mp": [50, 5.0], "atk": [4, 1.65], "def": [0, 0.3], "speed": 160, "crit": [0.06, 0.002],
		"basic": "ranged", "start_gear": {"weapon": "apprentice_staff"}, "start_items": {"health_potion": 2},
		"skills": ["ice_shard", "rain", "nova", "wave"]},
	"fire": {"name": "Pyromancer", "element": "fire", "role": "Burst ranged caster (fragile)",
		"desc": "Hỏa. Explosive fireballs and meteors that burn everything nearby. The biggest damage, the thinnest robes.",
		"hp": [26, 5.0], "mp": [45, 5.0], "atk": [3, 1.5], "def": [0, 0.2], "speed": 160, "crit": [0.10, 0.003],
		"basic": "ranged", "start_gear": {"weapon": "apprentice_staff"}, "start_items": {"health_potion": 3},
		"skills": ["fireball", "burst", "meteor", "inferno"]},
	"earth": {"name": "Stone Guardian", "element": "earth", "role": "Tank: HP, defense, stuns, taunt",
		"desc": "Thổ. Unmovable as a mountain: huge HP and armor, stuns with ground slams and pulls monsters off friends.",
		"hp": [40, 9.0], "mp": [30, 3.0], "atk": [4, 1.7], "def": [2, 0.6], "speed": 150, "crit": [0.05, 0.002],
		"basic": "melee", "start_gear": {"offhand": "wooden_shield"}, "start_items": {"health_potion": 2},
		"skills": ["slam", "stoneskin", "taunt", "quake"]},
}

const UNLOCK_LEVELS := [1, 3, 6, 10]

## Skill definitions. mult = damage multiplier of the caster's attack.
const SKILLS := {
	# ---- Metal
	"whirl": {"name": "Whirling Blade", "cost": 12, "cd": 4.0, "kind": "aoe_self", "radius": 72.0, "mult": 1.6,
		"desc": "Spin and slash every enemy around you (160% damage)."},
	"pierce": {"name": "Piercing Strike", "cost": 18, "cd": 7.0, "kind": "dash", "range": 130.0, "width": 34.0, "mult": 2.2, "crit": true,
		"desc": "Dash forward, cutting through everything in your path (220%, always crits)."},
	"focus": {"name": "Blade Focus", "cost": 20, "cd": 18.0, "kind": "buff", "duration": 6.0,
		"desc": "For 6 s: +40% critical chance and +25% attack."},
	"cuts": {"name": "Thousand Cuts", "cost": 35, "cd": 14.0, "kind": "multi_hit", "range": 90.0, "hits": 5, "mult": 0.9,
		"desc": "Five lightning-fast strikes on the nearest enemy (5 x 90%)."},
	# ---- Wood
	"thorn": {"name": "Poison Thorn", "cost": 10, "cd": 3.0, "kind": "projectile", "range": 300.0, "mult": 0.8,
		"proj": "thorn", "poison": [0.45, 5.0],
		"desc": "Hurl a thorn (80%) that poisons for 5 s (45%/s)."},
	"regrowth": {"name": "Regrowth", "cost": 20, "cd": 12.0, "kind": "hot", "instant": 0.10, "per_sec": 0.05, "duration": 5.0,
		"desc": "Heal 10% of max HP at once, then 5%/s for 5 s."},
	"roots": {"name": "Entangling Roots", "cost": 25, "cd": 12.0, "kind": "aoe_target", "range": 240.0, "radius": 90.0, "mult": 0.6,
		"stun": 1.5, "poison": [0.3, 4.0],
		"desc": "Roots erupt under the nearest enemy: 60% damage, roots (stun) 1.5 s and poisons nearby enemies."},
	"bloom": {"name": "Plague Bloom", "cost": 35, "cd": 16.0, "kind": "aoe_self", "radius": 130.0, "mult": 0.3,
		"poison": [0.8, 6.0],
		"desc": "A toxic bloom poisons every enemy around you for 6 s (80%/s)."},
	# ---- Water
	"ice_shard": {"name": "Ice Shard", "cost": 6, "cd": 2.0, "kind": "projectile", "range": 320.0, "mult": 1.4,
		"proj": "ice", "slow": [0.4, 3.0],
		"desc": "A piercing-cold shard (140%) that slows by 40% for 3 s."},
	"rain": {"name": "Healing Rain", "cost": 25, "cd": 10.0, "kind": "heal_area", "radius": 150.0, "heal": 0.25,
		"desc": "Heal yourself and all allies within range for 25% of their max HP."},
	"nova": {"name": "Frost Nova", "cost": 25, "cd": 12.0, "kind": "aoe_self", "radius": 110.0, "mult": 1.2, "stun": 1.5,
		"desc": "Freeze every enemy around you: 120% damage and frozen (stun) for 1.5 s."},
	"wave": {"name": "Tidal Wave", "cost": 35, "cd": 12.0, "kind": "projectile", "range": 360.0, "mult": 2.0,
		"proj": "wave", "pierce": true, "hit_radius": 34.0, "slow": [0.5, 3.0],
		"desc": "A wide wave that crashes through all enemies in a line (200%) and slows them by 50%."},
	# ---- Fire
	"fireball": {"name": "Fireball", "cost": 12, "cd": 3.0, "kind": "projectile", "range": 320.0, "mult": 1.8,
		"proj": "fire", "explode": 55.0, "burn": [0.3, 3.0],
		"desc": "Explodes on impact (180% in a small area) and burns for 3 s."},
	"burst": {"name": "Flame Burst", "cost": 20, "cd": 8.0, "kind": "aoe_self", "radius": 95.0, "mult": 2.0, "burn": [0.4, 4.0],
		"desc": "Erupt in flames: 200% to everything around you, burning for 4 s."},
	"meteor": {"name": "Meteor", "cost": 35, "cd": 14.0, "kind": "delayed_target", "range": 320.0, "radius": 105.0, "mult": 3.5,
		"delay": 0.8, "burn": [0.5, 4.0],
		"desc": "Call down a meteor on the nearest enemy: after 0.8 s, 350% in a large area and burning ground."},
	"inferno": {"name": "Inferno", "cost": 45, "cd": 16.0, "kind": "ring", "count": 12, "mult": 1.5, "proj": "fire", "burn": [0.3, 3.0],
		"desc": "Twelve fire bolts burst out in every direction (150% each)."},
	# ---- Earth
	"slam": {"name": "Ground Slam", "cost": 12, "cd": 5.0, "kind": "aoe_self", "radius": 80.0, "mult": 1.6, "stun": 1.0,
		"desc": "Smash the ground: 120% to nearby enemies and stun them for 1 s."},
	"stoneskin": {"name": "Stone Skin", "cost": 20, "cd": 15.0, "kind": "shield", "amount": 0.3, "duration": 8.0,
		"desc": "A stone shield absorbs damage equal to 30% of your max HP for 8 s."},
	"taunt": {"name": "Mountain's Challenge", "cost": 15, "cd": 12.0, "kind": "taunt", "radius": 230.0, "duration": 5.0,
		"desc": "Every monster within range attacks you; +50% defense for 5 s."},
	"quake": {"name": "Earthquake", "cost": 35, "cd": 16.0, "kind": "pulses", "radius": 140.0, "mult": 1.3, "pulses": 3,
		"interval": 0.6, "slow": [0.5, 2.0],
		"desc": "Three tremors (3 x 100%) around you that slow enemies by 50%."},
}


static func exists(cls: String) -> bool:
	return DB.has(cls)


static func info(cls: String) -> Dictionary:
	return DB.get(cls, DB["metal"])


static func element_of(cls: String) -> String:
	return str(info(cls)["element"])


static func color(element: String) -> Color:
	return ELEMENT_INFO.get(element, ELEMENT_INFO["metal"])["color"]


static func element_name(element: String) -> String:
	var e: Dictionary = ELEMENT_INFO.get(element, {})
	return "%s (%s)" % [e.get("name", "?"), e.get("viet", "?")]


## Damage multiplier for an attack of element `att` against a target of element `def_e`.
static func multiplier(att: String, def_e: String) -> float:
	if att == "" or def_e == "":
		return 1.0
	if OVERCOMES.get(att, "") == def_e:
		return STRONG
	if OVERCOMES.get(def_e, "") == att:
		return WEAK
	return 1.0


static func stat(cls: String, key: String, level: int) -> float:
	var v: Array = info(cls)[key]
	return float(v[0]) + float(v[1]) * float(level - 1)


static func skill_unlock_level(slot: int) -> int:
	return UNLOCK_LEVELS[clampi(slot, 0, 3)]


static func skill_id(cls: String, slot: int) -> String:
	var ks: Array = info(cls)["skills"]
	return str(ks[slot]) if slot >= 0 and slot < ks.size() else ""


static func skill_icon(skill: String) -> Texture2D:
	return load("res://assets/skills/%s.png" % skill)


static func element_icon(element: String, big := false) -> Texture2D:
	return load("res://assets/elements/%s%s.png" % [element, "_big" if big else ""])
