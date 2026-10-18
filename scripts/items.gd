class_name Items
## Static item database: stackable items (potions, materials, currency) and gear BASES.
## A piece of gear in the world/bag/equipment is an INSTANCE (see gear.gd):
##   {uid, base, rarity, ilvl, upg, mods: [[affix_id, stat, value, tier, kind], ...], name}
## Everything about items lives here so the server and the UI agree.

const SLOTS := ["weapon", "offhand", "helmet", "body", "gloves", "boots", "belt", "amulet", "ring1", "ring2"]
const SLOT_NAMES := {"weapon": "Weapon", "offhand": "Off-hand", "helmet": "Helmet", "body": "Body Armour",
	"gloves": "Gloves", "boots": "Boots", "belt": "Belt", "amulet": "Amulet", "ring1": "Ring", "ring2": "Ring"}
const BAG_SIZE := 40
const STASH_SIZE := 40

## Stackable items. type: currency (gold), material, consumable, orb (crafting currency)
const DB := {
	"gold": {"name": "Gold", "type": "currency", "desc": "Shiny coins."},
	"slime_gel": {"name": "Slime Gel", "type": "material", "desc": "Sticky. The blacksmith pays a little for it.", "sell": 1},
	"health_potion": {"name": "Health Potion", "type": "consumable", "heal": 15, "sell": 2, "desc": "Restores 15 HP."},
	"greater_potion": {"name": "Greater Potion", "type": "consumable", "heal": 40, "sell": 6, "desc": "Restores 40 HP."},
	"orb_transmute": {"name": "Orb of Transmutation", "type": "orb", "desc": "Upgrades a Normal item to Magic (1-2 affixes)."},
	"orb_alteration": {"name": "Orb of Alteration", "type": "orb", "desc": "Rerolls the affixes of a Magic item."},
	"orb_regal": {"name": "Regal Orb", "type": "orb", "desc": "Upgrades a Magic item to Rare, adding one affix (a Rare has at least 3)."},
	"orb_chaos": {"name": "Chaos Orb", "type": "orb", "desc": "Rerolls a Rare item with 3-6 new affixes."},
	"orb_exalt": {"name": "Exalted Orb", "type": "orb", "desc": "Adds one affix to a Rare item (max 6)."},
	"orb_scour": {"name": "Orb of Scouring", "type": "orb", "desc": "Removes all affixes: the item becomes Normal."},
	"enhance_stone": {"name": "Enhancement Stone (Huyen Tinh)", "type": "orb",
		"desc": "Blacksmith only: +1 upgrade level (+1..+10) boosting base stats. Costs gold; can fail. Above +5 a failure may drop a level, but the item is never destroyed."},
	"orb_chisel": {"name": "Cartographer's Chisel", "type": "orb", "desc": "Dungeon Tickets only: +5% quality (max 20%). Each 1% quality = +1% item quantity in the run."},
}
const ORBS := ["orb_transmute", "orb_alteration", "orb_regal", "orb_chaos", "orb_exalt", "orb_scour", "enhance_stone", "orb_chisel"]

## Gear bases. lvl = item level needed to drop AND level required to equip.
## damage (weapons) / defense (armour) are base stats boosted by upgrades; imp = implicit modifiers.
## drop: false -> only exists as a unique.
const BASES := {
	# dungeon tickets (endgame maps, see dungeons.gd) - not equippable, never rolled as gear
	"ticket_wood": {"name": "Forest Den Ticket", "slot": "ticket", "lvl": 1, "drop": false, "theme": "wood"},
	"ticket_water": {"name": "Frozen Vault Ticket", "slot": "ticket", "lvl": 1, "drop": false, "theme": "water"},
	"ticket_earth": {"name": "Stone Hollow Ticket", "slot": "ticket", "lvl": 1, "drop": false, "theme": "earth"},
	"ticket_fire": {"name": "Ember Caverns Ticket", "slot": "ticket", "lvl": 1, "drop": false, "theme": "fire"},
	"ticket_metal": {"name": "Metal Forge Ticket", "slot": "ticket", "lvl": 1, "drop": false, "theme": "metal"},
	# weapons
	"iron_sword": {"name": "Iron Sword", "slot": "weapon", "lvl": 1, "damage": 1},
	"apprentice_staff": {"name": "Apprentice Staff", "slot": "weapon", "lvl": 1, "damage": 1, "classes": ["wood", "water", "fire"]},
	"steel_sword": {"name": "Steel Sword", "slot": "weapon", "lvl": 4, "damage": 2},
	"war_axe": {"name": "War Axe", "slot": "weapon", "lvl": 6, "damage": 4, "classes": ["metal", "earth"]},
	"great_hammer": {"name": "Great Hammer", "slot": "weapon", "lvl": 10, "damage": 6, "classes": ["metal", "earth"]},
	"venom_dagger": {"name": "Venom Dagger", "slot": "weapon", "lvl": 6, "damage": 5, "classes": ["metal", "wood"], "drop": false},
	"lich_staff": {"name": "Lich Staff", "slot": "weapon", "lvl": 10, "damage": 7, "classes": ["wood", "water", "fire"]},
	"frostbrand": {"name": "Frostbrand", "slot": "weapon", "lvl": 13, "damage": 9, "classes": ["metal", "earth"], "drop": false},
	"ember_staff": {"name": "Ember Staff", "slot": "weapon", "lvl": 13, "damage": 9, "classes": ["wood", "water", "fire"], "drop": false},
	# off-hand
	"wooden_shield": {"name": "Wooden Shield", "slot": "offhand", "lvl": 1, "defense": 1},
	"iron_shield": {"name": "Iron Shield", "slot": "offhand", "lvl": 4, "defense": 2},
	"bone_shield": {"name": "Bone Shield", "slot": "offhand", "lvl": 8, "defense": 4},
	"frost_aegis": {"name": "Frost Aegis", "slot": "offhand", "lvl": 13, "defense": 6, "drop": false},
	# armour
	"leather_cap": {"name": "Leather Cap", "slot": "helmet", "lvl": 1, "defense": 1},
	"iron_helm": {"name": "Iron Helm", "slot": "helmet", "lvl": 6, "defense": 2},
	"horned_helm": {"name": "Horned Helm", "slot": "helmet", "lvl": 11, "defense": 3, "imp": {"life_flat": 10}},
	"cloth_robe": {"name": "Cloth Robe", "slot": "body", "lvl": 1, "defense": 1, "imp": {"mana_flat": 10}},
	"leather_vest": {"name": "Leather Vest", "slot": "body", "lvl": 3, "defense": 2},
	"chain_mail": {"name": "Chain Mail", "slot": "body", "lvl": 8, "defense": 4},
	"plate_armour": {"name": "Plate Armour", "slot": "body", "lvl": 12, "defense": 6, "classes": ["metal", "earth"]},
	"cloth_wraps": {"name": "Cloth Wraps", "slot": "gloves", "lvl": 1, "defense": 1},
	"iron_gauntlets": {"name": "Iron Gauntlets", "slot": "gloves", "lvl": 7, "defense": 2},
	"sandals": {"name": "Sandals", "slot": "boots", "lvl": 1, "defense": 0, "imp": {"speed_pct": 3}},
	"leather_boots": {"name": "Leather Boots", "slot": "boots", "lvl": 5, "defense": 1, "imp": {"speed_pct": 4}},
	"iron_greaves": {"name": "Iron Greaves", "slot": "boots", "lvl": 9, "defense": 2},
	# jewellery
	"rope_belt": {"name": "Rope Belt", "slot": "belt", "lvl": 1, "imp": {"life_flat": 5}},
	"leather_belt": {"name": "Leather Belt", "slot": "belt", "lvl": 6, "imp": {"life_flat": 12}},
	"jade_amulet": {"name": "Jade Amulet", "slot": "amulet", "lvl": 1, "imp": {"res_all": 3}},
	"coral_amulet": {"name": "Coral Amulet", "slot": "amulet", "lvl": 7, "imp": {"life_flat": 15}},
	"copper_ring": {"name": "Copper Ring", "slot": "ring", "lvl": 1, "imp": {"mana_flat": 5}},
	"jade_ring": {"name": "Jade Ring", "slot": "ring", "lvl": 5, "imp": {"res:wood": 8}},
	"silver_ring": {"name": "Silver Ring", "slot": "ring", "lvl": 9, "imp": {"crit": 1}},
}

## Hand-designed uniques: fixed modifiers (on top of the base). boss: only drops from that boss
## (guaranteed); otherwise it can drop anywhere from item level `lvl` (rare roll, see gear.gd).
const UNIQUES := {
	"venom_dagger": {"name": "Venom Dagger", "base": "venom_dagger", "lvl": 6, "boss": "broodmother",
		"mods": {"attack_speed": 10, "dot_poison": 25, "dmg_vs:earth": 15}, "flavour": "The Broodmother's fang, still dripping."},
	"lich_staff_u": {"name": "Soulbinder (Lich Staff)", "base": "lich_staff", "lvl": 10, "boss": "lich",
		"mods": {"mana_leech": 1.5, "mana_flat": 30, "cast_speed": 10, "res:metal": -10}, "flavour": "It hungers for minds."},
	"frostbrand": {"name": "Frostbrand", "base": "frostbrand", "lvl": 13, "boss": "yeti_king",
		"mods": {"dmg_vs:fire": 20, "res:water": 25, "attack_speed": 8}, "flavour": "Cold enough to cut flame."},
	"ember_staff": {"name": "Ember Staff", "base": "ember_staff", "lvl": 13, "boss": "yeti_king",
		"mods": {"cast_speed": 12, "dot_burn": 30, "ele_dmg_pct": 20, "res:water": -15}, "flavour": "Warm in a frozen king's grip."},
	"frost_aegis": {"name": "Frost Aegis", "base": "frost_aegis", "lvl": 13, "boss": "yeti_king",
		"mods": {"res:fire": 20, "res:water": 30, "life_flat": 30}, "flavour": "Ice that never melts."},
	# element-themed uniques that drop anywhere (rarely)
	"five_phases": {"name": "Ngu Hanh Band (Five Phases)", "base": "silver_ring", "lvl": 9,
		"mods": {"res_all": 12, "ele_dmg_pct": 10}, "flavour": "Metal, Wood, Water, Fire, Earth - in balance."},
	"golden_dragon": {"name": "Kim Long (Golden Dragon) Amulet", "base": "jade_amulet", "lvl": 5,
		"mods": {"dmg_vs:wood": 20, "crit": 4, "gold_find": 30}, "flavour": "Metal cuts the forest."},
	"thousand_leaf": {"name": "Moc Diep (Thousand-Leaf) Treads", "base": "leather_boots", "lvl": 5,
		"mods": {"speed_pct": 18, "res:metal": 20, "item_rarity": 15}, "flavour": "Light as falling leaves."},
	"river_heart": {"name": "Thuy Tam (River Heart) Circlet", "base": "iron_helm", "lvl": 6,
		"mods": {"mana_flat": 40, "mp_regen_pct": 30, "res:fire": 25}, "flavour": "Water quenches fire."},
	"emberfist": {"name": "Hoa Quyen (Emberfist)", "base": "iron_gauntlets", "lvl": 7,
		"mods": {"dmg_flat": 6, "dot_burn": 20, "attack_speed": 8, "res:water": -10}, "flavour": "Burns the hand that wields it."},
	"mountain_root": {"name": "Tho Son (Mountain-Root) Girdle", "base": "leather_belt", "lvl": 6,
		"mods": {"life_flat": 60, "def_flat": 4, "res:wood": 20, "speed_pct": -5}, "flavour": "Heavy as the mountain."},
	"wuxing_sanctum": {"name": "Sanctum of the Five Phases", "base": "ticket_metal", "lvl": 1, "tier": 8, "boss": "dungeon",
		"mods": {"map_mon_hp": 60, "map_extra_ele": 30, "map_elites": 3, "map_less_res": 20}, "flavour": "Every element at once. Bring every resistance."},
	"gold_seeker": {"name": "Gold Seeker's Ring", "base": "copper_ring", "lvl": 3,
		"mods": {"item_quantity": 12, "item_rarity": 25, "gold_find": 40, "atk_pct": -10}, "flavour": "Fortune favours the greedy."},
}

static var _icons := {}


## True for stackables AND gear bases.
static func exists(id: String) -> bool:
	return DB.has(id) or BASES.has(id)


static func info(id: String) -> Dictionary:
	if DB.has(id):
		return DB[id]
	if BASES.has(id):
		return BASES[id]
	return {"name": id, "type": "material", "desc": ""}


static func is_base(id: String) -> bool:
	return BASES.has(id)


static func display_name(id: String) -> String:
	return str(info(id)["name"])


static func type_of(id: String) -> String:
	if BASES.has(id):
		return "gear"
	return str(info(id).get("type", "material"))


## Bag/equipment slot family of a base ("ring" for both ring slots), "" if not gear.
static func slot_for(id: String) -> String:
	return str(BASES[id]["slot"]) if BASES.has(id) else ""


## Equipment slots a base fits in.
static func slots_for(id: String) -> Array:
	var s := slot_for(id)
	if s == "ring":
		return ["ring1", "ring2"]
	if s == "ticket":
		return []
	return [s] if s != "" else []


static func stat(id: String, key: String) -> int:
	return int(info(id).get(key, 0))


## Class restriction ("" class = anyone; bases without "classes" = anyone).
static func can_use(id: String, cls: String) -> bool:
	var c: Array = info(id).get("classes", [])
	return c.is_empty() or cls == "" or cls in c


static func class_note(id: String) -> String:
	var c: Array = info(id).get("classes", [])
	if c.is_empty():
		return ""
	var names: Array = []
	for k in c:
		names.append(Classes.info(k)["name"])
	return "Only: " + ", ".join(names)


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://assets/items/%s.png" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]
