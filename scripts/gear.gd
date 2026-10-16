class_name Gear
## Gear instances, rarity, affixes, crafting currency and enhancement (Vo Lam x Path of Exile).
## The SERVER does every roll (it owns the RandomNumberGenerator); clients only display.
##
## Instance: {uid, base, rarity: normal|magic|rare|unique, ilvl, upg (0..10),
##            mods: [[affix_id, stat, value, tier, kind("p"|"s"|"u")], ...], name (rare/unique), uniq (unique id)}
## Gear.mods(inst) returns its modifier dictionary (implicit + affixes + upgrade bonus) - this is
## what Stats.gather() reads for every equipped item.

const RARITIES := ["normal", "magic", "rare", "unique"]
const RARITY_COLOR := {"normal": Color(0.92, 0.92, 0.92), "magic": Color(0.45, 0.6, 1.0),
	"rare": Color(1.0, 0.9, 0.3), "unique": Color(1.0, 0.55, 0.15)}
const RES_CAP := 75.0
const MAX_UPG := 10
const BASE_CHANCE := {"unique": 0.012, "rare": 0.09, "magic": 0.32}   # before item rarity
## enhancement success chance for the NEXT level (index = current upg)
const ENHANCE_CHANCE := [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]
const DOWNGRADE_CHANCE := 0.5   # on a failed attempt from +5 or higher

const JEWEL := ["ring", "amulet"]
const ARMOUR := ["offhand", "helmet", "body", "gloves", "boots"]
const ELEMENTS := ["metal", "wood", "water", "fire", "earth"]

## Affix pools. tiers: [min_ilvl, lo, hi]; slots: slot families the affix can roll on.
## "{el}" in id/stat expands to one affix per element; "{skill}" picks a skill of the killer's class.
const PREFIXES := [
	{"id": "life", "stat": "life_flat", "tiers": [[1, 5, 10], [5, 11, 18], [10, 19, 28], [14, 29, 40]], "slots": ["offhand", "helmet", "body", "gloves", "boots", "belt", "amulet", "ring"], "w": 10},
	{"id": "mana", "stat": "mana_flat", "tiers": [[1, 5, 10], [6, 11, 20], [12, 21, 32]], "slots": ["weapon", "helmet", "body", "gloves", "boots", "belt", "amulet", "ring"], "w": 8},
	{"id": "flat_dmg", "stat": "dmg_flat", "tiers": [[1, 1, 2], [5, 3, 4], [9, 5, 7], [13, 8, 10]], "slots": ["weapon", "gloves", "ring", "amulet"], "w": 9},
	{"id": "pct_dmg", "stat": "atk_pct", "tiers": [[1, 5, 9], [6, 10, 16], [11, 17, 25]], "slots": ["weapon", "amulet"], "w": 7},
	{"id": "ele_dmg", "stat": "ele_dmg_pct", "tiers": [[1, 6, 10], [7, 11, 18], [12, 19, 28]], "slots": ["weapon", "amulet", "ring"], "w": 7},
	{"id": "armour", "stat": "def_flat", "tiers": [[1, 1, 2], [6, 3, 4], [11, 5, 7]], "slots": ["offhand", "helmet", "body", "gloves", "boots", "belt"], "w": 8},
	{"id": "slay_{el}", "stat": "dmg_vs:{el}", "tiers": [[1, 6, 10], [8, 11, 18], [13, 19, 26]], "slots": ["weapon", "ring", "amulet", "gloves"], "w": 3},
	{"id": "rarity_p", "stat": "item_rarity", "tiers": [[1, 4, 8], [6, 9, 14], [12, 15, 22]], "slots": ["helmet", "boots", "gloves", "amulet", "ring"], "w": 5},
	{"id": "skill", "stat": "dmg:{skill}", "tiers": [[3, 10, 16], [9, 17, 26], [14, 27, 36]], "slots": ["weapon", "amulet"], "w": 5},
	# map modifiers (Dungeon Tickets only; ticket item level = 2 x tier)
	{"id": "m_hp", "stat": "map_mon_hp", "tiers": [[1, 20, 30], [6, 31, 45], [12, 46, 60]], "slots": ["ticket"], "w": 10},
	{"id": "m_dmg", "stat": "map_mon_dmg", "tiers": [[1, 12, 20], [6, 21, 30], [12, 31, 40]], "slots": ["ticket"], "w": 10},
	{"id": "m_ele", "stat": "map_extra_ele", "tiers": [[1, 10, 15], [6, 16, 25], [12, 26, 35]], "slots": ["ticket"], "w": 8},
	{"id": "m_packs", "stat": "map_packs", "tiers": [[1, 20, 30], [8, 31, 50]], "slots": ["ticket"], "w": 8},
	{"id": "m_elites", "stat": "map_elites", "tiers": [[3, 1, 1], [10, 2, 3]], "slots": ["ticket"], "w": 6},
	{"id": "m_speed", "stat": "map_mon_speed", "tiers": [[1, 10, 15], [8, 16, 25]], "slots": ["ticket"], "w": 7},
]
const SUFFIXES := [
	{"id": "res_{el}", "stat": "res:{el}", "tiers": [[1, 6, 11], [5, 12, 17], [10, 18, 24], [14, 25, 30]], "slots": ["offhand", "helmet", "body", "gloves", "boots", "belt", "amulet", "ring"], "w": 5},
	{"id": "res_all", "stat": "res_all", "tiers": [[8, 3, 5], [13, 6, 9]], "slots": ["amulet", "ring"], "w": 4},
	{"id": "aspd", "stat": "attack_speed", "tiers": [[1, 3, 5], [7, 6, 9], [12, 10, 13]], "slots": ["weapon", "gloves", "ring"], "w": 7},
	{"id": "cspd", "stat": "cast_speed", "tiers": [[1, 3, 5], [7, 6, 9], [12, 10, 13]], "slots": ["weapon", "amulet", "ring"], "w": 7},
	{"id": "crit", "stat": "crit", "tiers": [[1, 1, 2], [6, 2, 3], [11, 3, 5]], "slots": ["weapon", "amulet", "ring", "gloves"], "w": 6},
	{"id": "critx", "stat": "crit_dmg", "tiers": [[5, 8, 14], [11, 15, 24]], "slots": ["weapon", "amulet"], "w": 5},
	{"id": "lleech", "stat": "life_leech", "tiers": [[4, 0.4, 0.8], [10, 0.9, 1.5]], "slots": ["weapon", "ring", "gloves"], "w": 4},
	{"id": "mleech", "stat": "mana_leech", "tiers": [[4, 0.4, 0.8], [10, 0.9, 1.5]], "slots": ["weapon", "ring", "gloves"], "w": 4},
	{"id": "move", "stat": "speed_pct", "tiers": [[1, 4, 7], [6, 8, 11], [11, 12, 16]], "slots": ["boots"], "w": 10},
	{"id": "quantity", "stat": "item_quantity", "tiers": [[5, 3, 5], [11, 6, 9]], "slots": ["ring", "amulet", "belt", "boots"], "w": 4},
	{"id": "gold", "stat": "gold_find", "tiers": [[1, 5, 10], [6, 11, 18], [11, 19, 28]], "slots": ["ring", "amulet", "belt", "gloves", "helmet"], "w": 6},
	{"id": "m_res", "stat": "map_less_res", "tiers": [[1, 8, 12], [6, 13, 20], [12, 21, 30]], "slots": ["ticket"], "w": 9},
	{"id": "m_noregen", "stat": "map_no_regen", "tiers": [[4, 1, 1]], "slots": ["ticket"], "w": 4},
	{"id": "m_mana", "stat": "map_less_mana_regen", "tiers": [[1, 20, 30], [8, 31, 50]], "slots": ["ticket"], "w": 7},
	{"id": "m_def", "stat": "map_mon_def", "tiers": [[1, 2, 3], [8, 4, 6]], "slots": ["ticket"], "w": 7},
	{"id": "mregen", "stat": "mp_regen_pct", "tiers": [[1, 8, 14], [7, 15, 24]], "slots": ["helmet", "body", "belt", "amulet", "ring", "offhand"], "w": 6},
]
const RARE_A := ["Grim", "Storm", "Jade", "Ashen", "Dragon", "Viper", "Iron", "Tiger", "Phoenix", "Shadow",
	"Thunder", "Crimson", "Frost", "Golden", "Hollow", "Rune", "Spirit", "Wolf", "Ember", "Cloud"]
const RARE_B := {"weapon": ["Bite", "Fang", "Edge", "Song", "Wrath", "Thirst"],
	"offhand": ["Ward", "Bulwark", "Guard", "Wall"], "helmet": ["Crown", "Visage", "Brow", "Dome"],
	"body": ["Shell", "Mantle", "Coat", "Hide"], "gloves": ["Grasp", "Fist", "Clutch", "Touch"],
	"boots": ["Stride", "Track", "Trail", "Pace"], "belt": ["Coil", "Girdle", "Cord", "Clasp"],
	"amulet": ["Charm", "Talisman", "Heart", "Eye"], "ring": ["Loop", "Circle", "Band", "Whorl"],
	"ticket": ["Labyrinth", "Maze", "Lair", "Depths", "Sanctum", "Hollow"]}
const CURRENCY_CHANCE := 0.09
const CURRENCY_WEIGHTS := {"orb_transmute": 30, "orb_alteration": 26, "enhance_stone": 22, "orb_scour": 8,
	"orb_regal": 7, "orb_chaos": 5, "orb_exalt": 2, "orb_chisel": 6}


# ---------------------------------------------------------------- basics

static func slot_family(inst: Dictionary) -> String:
	return Items.slot_for(str(inst.get("base", "")))


static func new_uid(rng: RandomNumberGenerator) -> int:
	return rng.randi() & 0x3fffffff


static func base_lvl(inst: Dictionary) -> int:
	return Items.stat(str(inst.get("base", "")), "lvl")


## Level required to equip: the base level, raised by high affix tiers; uniques use their own level.
static func req_level(inst: Dictionary) -> int:
	if Dungeons.is_ticket(inst):
		return 1
	var r := base_lvl(inst)
	if inst.get("rarity") == "unique":
		return maxi(r, int(Items.UNIQUES.get(str(inst.get("uniq", "")), {}).get("lvl", r)))
	for m in inst.get("mods", []):
		r = maxi(r, int(floor(_tier_min(str(m[0]), int(m[3])) * 0.8)))
	return r


static func _tier_min(affix_id: String, tier: int) -> int:
	var a := _affix_def(affix_id)
	if a.is_empty():
		return 1
	return int(a["tiers"][clampi(tier, 0, a["tiers"].size() - 1)][0])


static func _affix_def(affix_id: String) -> Dictionary:
	for pool in [PREFIXES, SUFFIXES]:
		for a in pool:
			var id: String = a["id"]
			if id == affix_id:
				return a
			if "{el}" in id:
				for e in ELEMENTS:
					if id.replace("{el}", e) == affix_id:
						return a
	return {}


static func damage(inst: Dictionary) -> int:
	var b := Items.stat(str(inst.get("base", "")), "damage")
	if b <= 0:
		return 0
	var u := int(inst.get("upg", 0))
	return b + u + int(floor(b * 0.1 * u))


static func defense(inst: Dictionary) -> int:
	var base := str(inst.get("base", ""))
	if not Items.BASES.has(base) or not Items.BASES[base].has("defense"):
		return 0
	var b := Items.stat(base, "defense")
	return b + int(ceil(int(inst.get("upg", 0)) * 0.5))


## Modifier dictionary of one item: implicit + affixes (+ upgrade bonus on jewellery/belts).
static func mods(inst: Dictionary) -> Dictionary:
	var m := {}
	if inst.is_empty() or not Items.BASES.has(str(inst.get("base", ""))):
		return m
	var b: Dictionary = Items.BASES[str(inst["base"])]
	for k in b.get("imp", {}):
		m[k] = float(m.get(k, 0.0)) + float(b["imp"][k])
	for e in inst.get("mods", []):
		m[str(e[1])] = float(m.get(str(e[1]), 0.0)) + float(e[2])
	var u := int(inst.get("upg", 0))
	if u > 0 and damage(inst) == 0 and defense(inst) == 0:
		m["life_flat"] = float(m.get("life_flat", 0.0)) + 3.0 * u
	return m


static func display_name(inst: Dictionary) -> String:
	var base_name := Items.display_name(str(inst.get("base", "")))
	var n := base_name
	match str(inst.get("rarity", "normal")):
		"magic":
			var pre := ""
			var suf := ""
			for e in inst.get("mods", []):
				if e[4] == "p" and pre == "":
					pre = _affix_word(str(e[0]), true)
				elif e[4] == "s" and suf == "":
					suf = _affix_word(str(e[0]), false)
			n = ("%s %s %s" % [pre, base_name, suf]).strip_edges()
		"rare", "unique":
			n = str(inst.get("name", base_name))
	if Dungeons.is_ticket(inst):
		return "%s (T%d)" % [n, Dungeons.tier_of(inst)]
	var u := int(inst.get("upg", 0))
	return ("+%d %s" % [u, n]) if u > 0 else n


static func _affix_word(id: String, prefix: bool) -> String:
	var words := {"life": "Hale", "mana": "Wise", "flat_dmg": "Sharp", "pct_dmg": "Cruel", "ele_dmg": "Elemental",
		"armour": "Sturdy", "rarity_p": "Lucky", "skill": "Adept", "res_all": "of the Five Phases", "aspd": "of Haste",
		"cspd": "of Incantation", "crit": "of Precision", "critx": "of Ruin", "lleech": "of the Leech",
		"mleech": "of Thirst", "move": "of the Wind", "quantity": "of Plenty", "gold": "of Greed", "mregen": "of the Spring",
		"m_hp": "Fecund", "m_dmg": "Savage", "m_ele": "Chromatic", "m_packs": "Teeming", "m_elites": "Champion's",
		"m_speed": "Restless", "m_res": "of Exposure", "m_noregen": "of Stasis", "m_mana": "of Drought", "m_def": "of Iron Hides"}
	if words.has(id):
		return words[id]
	if id.begins_with("slay_"):
		return "%s-slaying" % Classes.ELEMENT_INFO[id.trim_prefix("slay_")]["name"]
	if id.begins_with("res_"):
		return "of %s Warding" % Classes.ELEMENT_INFO[id.trim_prefix("res_")]["name"]
	return "Strange" if prefix else "of Mystery"


# ---------------------------------------------------------------- rolling

static func _prefix_count(inst: Dictionary, kind: String) -> int:
	var n := 0
	for e in inst.get("mods", []):
		if e[4] == kind:
			n += 1
	return n


## Adds one random affix allowed for this item (ilvl gate, slot, no duplicate). False if none fits.
static func add_affix(inst: Dictionary, rng: RandomNumberGenerator, cls: String, kind := "") -> bool:
	var max_side := 1 if inst["rarity"] == "magic" else 3
	var sides: Array = []
	if kind != "":
		sides = [kind]
	else:
		if _prefix_count(inst, "p") < max_side:
			sides.append("p")
		if _prefix_count(inst, "s") < max_side:
			sides.append("s")
	if sides.is_empty():
		return false
	var fam := slot_family(inst)
	var ilvl := int(inst.get("ilvl", 1))
	var taken := {}
	for e in inst.get("mods", []):
		taken[str(e[0])] = true
		taken[str(e[1])] = true
	var cands: Array = []   # [weight, id, stat, def, kind]
	for side in sides:
		for a in (PREFIXES if side == "p" else SUFFIXES):
			if not fam in a["slots"] or int(a["tiers"][0][0]) > ilvl:
				continue
			var ids: Array = []
			if "{el}" in a["id"]:
				for e in ELEMENTS:
					ids.append([a["id"].replace("{el}", e), a["stat"].replace("{el}", e), float(a["w"]) / 2.0])
			elif "{skill}" in a["stat"]:
				var c: String = cls if Classes.ELEMENTS.has(cls) else ELEMENTS[rng.randi() % 5]
				var sk: String = Classes.info(c)["skills"][rng.randi() % 4]
				ids.append([a["id"], a["stat"].replace("{skill}", sk), float(a["w"])])
			else:
				ids.append([a["id"], a["stat"], float(a["w"])])
			for x in ids:
				if not taken.has(x[0]) and not taken.has(x[1]):
					cands.append([x[2], x[0], x[1], a, side])
	if cands.is_empty():
		return false
	var total := 0.0
	for c in cands:
		total += c[0]
	var r := rng.randf() * total
	var pick: Array = cands[0]
	for c in cands:
		r -= c[0]
		if r <= 0.0:
			pick = c
			break
	var tiers: Array = pick[3]["tiers"]
	var ok_t: Array = []
	for t in tiers.size():
		if int(tiers[t][0]) <= ilvl:
			ok_t.append(t)
	var ti: int = ok_t[rng.randi() % ok_t.size()]
	var lo := float(tiers[ti][1])
	var hi := float(tiers[ti][2])
	var v: float
	if lo != floorf(lo) or hi != floorf(hi):
		v = snappedf(rng.randf_range(lo, hi), 0.1)
	else:
		v = float(rng.randi_range(int(lo), int(hi)))
	inst["mods"].append([pick[1], pick[2], v, ti, pick[4]])
	return true


static func _roll_affixes(inst: Dictionary, rng: RandomNumberGenerator, cls: String) -> void:
	inst["mods"] = []
	var n := 0
	match inst["rarity"]:
		"magic":
			n = rng.randi_range(1, 2)
		"rare":
			n = rng.randi_range(3, 6)
	for i in n:
		if not add_affix(inst, rng, cls):
			break
	if inst["rarity"] == "rare":
		inst["name"] = "%s %s" % [RARE_A[rng.randi() % RARE_A.size()], RARE_B[slot_family(inst)][rng.randi() % RARE_B[slot_family(inst)].size()]]
	else:
		inst.erase("name")


static func make(base: String, rarity: String, ilvl: int, rng: RandomNumberGenerator, cls := "") -> Dictionary:
	var inst := {"uid": new_uid(rng), "base": base, "rarity": rarity, "ilvl": ilvl, "upg": 0, "mods": []}
	if rarity != "normal":
		_roll_affixes(inst, rng, cls)
	return inst


static func make_unique(uid_id: String, ilvl: int, rng: RandomNumberGenerator) -> Dictionary:
	var u: Dictionary = Items.UNIQUES[uid_id]
	var inst := {"uid": new_uid(rng), "base": u["base"], "rarity": "unique", "ilvl": maxi(ilvl, int(u["lvl"])), "upg": 0,
		"mods": [], "name": u["name"], "uniq": uid_id}
	for k in u["mods"]:
		inst["mods"].append(["u_" + str(k), str(k), float(u["mods"][k]), 0, "u"])
	return inst


## Random droppable base whose level <= ilvl (newer bases weighted up).
static func roll_base(ilvl: int, rng: RandomNumberGenerator) -> String:
	var cands: Array = []
	var total := 0.0
	for id in Items.BASES:
		var b: Dictionary = Items.BASES[id]
		if b.get("drop", true) and int(b["lvl"]) <= ilvl:
			var w := 1.0 + float(b["lvl"]) / float(maxi(1, ilvl))
			cands.append([w, id])
			total += w
	var r := rng.randf() * total
	for c in cands:
		r -= c[0]
		if r <= 0.0:
			return c[1]
	return cands[-1][1]


## Rarity roll; iir = total increased item rarity % (player + monster).
static func roll_rarity(rng: RandomNumberGenerator, iir: float, min_rarity := "normal") -> String:
	var mult := maxf(0.0, 1.0 + iir / 100.0)
	var r := "normal"
	if rng.randf() < BASE_CHANCE["unique"] * mult:
		r = "unique"
	elif rng.randf() < BASE_CHANCE["rare"] * mult:
		r = "rare"
	elif rng.randf() < BASE_CHANCE["magic"] * mult:
		r = "magic"
	if RARITIES.find(r) < RARITIES.find(min_rarity):
		r = min_rarity
	return r


## Uniques that may drop at this item level (not boss-exclusive).
static func world_uniques(ilvl: int) -> Array:
	var out: Array = []
	for id in Items.UNIQUES:
		var u: Dictionary = Items.UNIQUES[id]
		if not u.has("boss") and int(u["lvl"]) <= ilvl:
			out.append(id)
	return out


## One gear drop. A "unique" rarity picks a world unique (or falls back to rare if none fits).
static func roll_drop(ilvl: int, rng: RandomNumberGenerator, iir: float, cls := "", min_rarity := "normal") -> Dictionary:
	var rarity := roll_rarity(rng, iir, min_rarity)
	if rarity == "unique":
		var pool := world_uniques(ilvl)
		if not pool.is_empty():
			return make_unique(pool[rng.randi() % pool.size()], ilvl, rng)
		rarity = "rare"
	return make(roll_base(ilvl, rng), rarity, ilvl, rng, cls)


static func roll_currency(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in CURRENCY_WEIGHTS:
		total += int(CURRENCY_WEIGHTS[k])
	var r := rng.randi() % total
	for k in CURRENCY_WEIGHTS:
		r -= int(CURRENCY_WEIGHTS[k])
		if r < 0:
			return k
	return "orb_transmute"


# ---------------------------------------------------------------- monster loot tables

## Item level of a monster's drops: its level (+2 for bosses).
static func monster_ilvl(d: Dictionary, level: int) -> int:
	return level + (2 if d.get("boss", false) else 0)


## Rolls a monster's loot table (except gold). Entries: [id, chance, count?, min_rarity?]
##   "@gear" random gear for the item level, "@currency" crafting currency, "u:<id>" a unique,
##   anything else = a stackable item id. Every non-summon also rolls CURRENCY_CHANCE for currency.
## Quantity (player + monster IIQ) multiplies chances; above 100% the extra becomes extra rolls for
## gear/currency. Rarity (player + monster IIR) feeds roll_rarity(). Returns [[item_id, count, inst], ...]
static func roll_monster_loot(d: Dictionary, level: int, iiq: float, iir: float, rng: RandomNumberGenerator, debug_mult := 1.0, cls := "") -> Array:
	var out: Array = []
	var boss: bool = d.get("boss", false)
	var ilvl := monster_ilvl(d, level)
	var q := maxf(0.0, 1.0 + (iiq + float(d.get("iiq", 0))) / 100.0)
	var r := iir + float(d.get("iir", 0))
	var table: Array = d.get("loot", []).duplicate()
	table.append(["@currency", 3.0 if boss else CURRENCY_CHANCE])
	for entry in table:
		var id := str(entry[0])
		var chance := float(entry[1])
		if not boss:
			chance *= debug_mult
		var multi := id == "@gear" or id == "@currency"
		chance *= q
		var rolls := 0
		if multi:
			rolls = int(floor(chance)) + (1 if rng.randf() < chance - floor(chance) else 0)
		else:
			rolls = 1 if rng.randf() < minf(1.0, chance) else 0
		var count := int(entry[2]) if entry.size() > 2 else 1
		for i in rolls:
			if id == "@gear":
				for c in count:
					var inst := roll_drop(ilvl, rng, r, cls, str(entry[3]) if entry.size() > 3 else "normal")
					out.append([str(inst["base"]), 1, inst])
			elif id == "@currency":
				out.append([roll_currency(rng), 1, {}])
			elif id.begins_with("u:"):
				var inst := make_unique(id.trim_prefix("u:"), ilvl, rng)
				out.append([str(inst["base"]), 1, inst])
			else:
				out.append([id, count, {}])
	return out


# ---------------------------------------------------------------- crafting (server)

## Applies an orb to an item in place. Returns "" on success or the reason it's invalid.
static func apply_orb(inst: Dictionary, orb: String, rng: RandomNumberGenerator, cls: String) -> String:
	var r := str(inst.get("rarity", "normal"))
	if r == "unique":
		return "uniques can't be modified with orbs"
	match orb:
		"orb_transmute":
			if r != "normal":
				return "Transmutation needs a Normal item (this is %s)" % r.capitalize()
			inst["rarity"] = "magic"
			_roll_affixes(inst, rng, cls)
		"orb_alteration":
			if r != "magic":
				return "Alteration needs a Magic item (this is %s)" % r.capitalize()
			_roll_affixes(inst, rng, cls)
		"orb_regal":
			if r != "magic":
				return "Regal needs a Magic item (this is %s)" % r.capitalize()
			inst["rarity"] = "rare"
			inst["name"] = "%s %s" % [RARE_A[rng.randi() % RARE_A.size()], RARE_B[slot_family(inst)][rng.randi() % RARE_B[slot_family(inst)].size()]]
			add_affix(inst, rng, cls)
			while inst["mods"].size() < 3 and add_affix(inst, rng, cls):   # a Rare always has 3+ affixes
				pass
		"orb_chaos":
			if r != "rare":
				return "Chaos needs a Rare item (this is %s)" % r.capitalize()
			_roll_affixes(inst, rng, cls)
		"orb_exalt":
			if r != "rare":
				return "Exalted needs a Rare item (this is %s)" % r.capitalize()
			if inst["mods"].size() >= 6:
				return "this Rare already has 6 affixes"
			if not add_affix(inst, rng, cls):
				return "no affix can be added to this item"
		"orb_chisel":
			if not Dungeons.is_ticket(inst):
				return "the Chisel only works on Dungeon Tickets"
			if int(inst.get("q", 0)) >= Dungeons.MAX_QUALITY:
				return "this ticket is already at %d%% quality" % Dungeons.MAX_QUALITY
			inst["q"] = mini(Dungeons.MAX_QUALITY, int(inst.get("q", 0)) + Dungeons.CHISEL_STEP)
		"orb_scour":
			if r == "normal":
				return "the item is already Normal"
			inst["rarity"] = "normal"
			inst["mods"] = []
			inst.erase("name")
		_:
			return "that is not a crafting orb"
	return ""


static func enhance_gold(upg: int) -> int:
	return 10 * (upg + 1) * (upg + 1)


## Vo Lam style enhancement. Returns {ok, err, result: "success"|"fail"|"downgrade", from, to, chance}.
static func enhance(inst: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var u := int(inst.get("upg", 0))
	if u >= MAX_UPG:
		return {"ok": false, "err": "already at +%d (max)" % MAX_UPG}
	var chance: float = ENHANCE_CHANCE[u]
	var res := {"ok": true, "from": u, "chance": chance}
	if rng.randf() < chance:
		inst["upg"] = u + 1
		res["result"] = "success"
	elif u >= 5 and rng.randf() < DOWNGRADE_CHANCE:
		inst["upg"] = u - 1
		res["result"] = "downgrade"
	else:
		res["result"] = "fail"
	res["to"] = int(inst["upg"])
	return res


static func sell_price(inst: Dictionary) -> int:
	if Dungeons.is_ticket(inst):
		return 3 + 4 * Dungeons.tier_of(inst) + 3 * inst.get("mods", []).size()
	var il := int(inst.get("ilvl", 1))
	var p: int = {"normal": 2 + il, "magic": 5 + 2 * il, "rare": 12 + 3 * il, "unique": 40 + 4 * il}.get(str(inst.get("rarity", "normal")), 1)
	return p + 10 * int(inst.get("upg", 0))


## Old saves stored plain item ids: turn one into an instance.
static func from_legacy(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var legacy_unique := {"venom_dagger": "venom_dagger", "lich_staff": "lich_staff_u", "frostbrand": "frostbrand",
		"ember_staff": "ember_staff", "frost_aegis": "frost_aegis"}
	if legacy_unique.has(id):
		return make_unique(legacy_unique[id], Items.stat(id, "lvl"), rng)
	return make(id, "normal", Items.stat(id, "lvl"), rng)


## Validates an instance from a save / network (drops unknown bases, fixes types).
static func sanitize(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY or not Items.BASES.has(str(v.get("base", ""))):
		return {}
	var inst := {"uid": int(v.get("uid", 0)), "base": str(v["base"]), "rarity": str(v.get("rarity", "normal")),
		"ilvl": int(v.get("ilvl", 1)), "upg": clampi(int(v.get("upg", 0)), 0, MAX_UPG), "mods": []}
	if not inst["rarity"] in RARITIES:
		inst["rarity"] = "normal"
	for e in v.get("mods", []):
		if typeof(e) == TYPE_ARRAY and e.size() == 5:
			inst["mods"].append([str(e[0]), str(e[1]), float(e[2]), int(e[3]), str(e[4])])
	if v.has("name"):
		inst["name"] = str(v["name"])
	if v.has("uniq"):
		inst["uniq"] = str(v["uniq"])
	if bool(v.get("bound", false)):
		inst["bound"] = true      # account-bound: can't be listed on the market
	if Dungeons.is_ticket(inst):
		inst["tier"] = clampi(int(v.get("tier", 1)), 1, Dungeons.MAX_TIER)
		inst["q"] = clampi(int(v.get("q", 0)), 0, Dungeons.MAX_QUALITY)
		inst["upg"] = 0
	return inst


# ---------------------------------------------------------------- text

## Rough "is this better" score for bots (damage/defense/life/res/etc).
static func score(inst: Dictionary) -> float:
	if inst.is_empty():
		return 0.0
	var sc := damage(inst) * 4.0 + defense(inst) * 3.0
	var m := mods(inst)
	for k in m:
		var v := float(m[k])
		if k in ["life_flat", "mana_flat"]:
			sc += v * 0.25
		elif k == "dmg_flat":
			sc += v * 3.0
		else:
			sc += v * 0.3
	return sc + RARITIES.find(str(inst.get("rarity", "normal"))) * 0.5


## One-line summary for logs.
static func summary(inst: Dictionary) -> String:
	if inst.is_empty():
		return "-"
	if Dungeons.is_ticket(inst):
		var ri := Dungeons.run_info(inst)
		return "[%s] %s (%s T%d, %d mods, q%d, iiq +%d%% iir +%d%%)" % [inst["rarity"], display_name(inst), inst["base"], Dungeons.tier_of(inst),
			inst["mods"].size(), int(inst.get("q", 0)), roundi(ri["iiq"]), roundi(ri["iir"])]
	return "[%s] %s (%s ilvl %d%s%s)" % [inst["rarity"], display_name(inst), inst["base"], int(inst.get("ilvl", 1)),
		(" +%d" % int(inst["upg"])) if int(inst.get("upg", 0)) > 0 else "",
		(", %d affixes" % inst["mods"].size()) if inst["rarity"] in ["magic", "rare"] else ""]


## Tooltip lines: [[text, Color], ...]
static func tooltip(inst: Dictionary, cls := "", level := 99) -> Array:
	var out := _tooltip(inst, cls, level)
	if bool(inst.get("bound", false)):
		out.append(["Account-bound (can't be traded)", Color(1.0, 0.55, 0.45)])
	return out


static func _tooltip(inst: Dictionary, cls := "", level := 99) -> Array:
	if Dungeons.is_ticket(inst):
		return Dungeons.tooltip(inst)
	var out: Array = []
	var col: Color = RARITY_COLOR.get(str(inst.get("rarity", "normal")), Color.WHITE)
	out.append([display_name(inst), col])
	var base := str(inst.get("base", ""))
	var r := str(inst.get("rarity", "normal")).capitalize()
	out.append(["%s %s  -  %s  (item level %d)" % [r, Items.display_name(base), Items.SLOT_NAMES.get(Items.slot_for(base), "Ring"), int(inst.get("ilvl", 1))], Color(0.7, 0.7, 0.75)])
	if damage(inst) > 0:
		out.append(["Damage: +%d%s" % [damage(inst), "  (+%d upgrade)" % (damage(inst) - Items.stat(base, "damage")) if int(inst.get("upg", 0)) > 0 else ""], Color(1, 1, 1)])
	if defense(inst) > 0:
		out.append(["Defense: +%d%s" % [defense(inst), "  (+%d upgrade)" % (defense(inst) - Items.stat(base, "defense")) if int(inst.get("upg", 0)) > 0 else ""], Color(1, 1, 1)])
	var b: Dictionary = Items.BASES.get(base, {})
	for line in Stats.describe(b.get("imp", {})):
		out.append([line + "  (implicit)", Color(0.75, 0.85, 1.0)])
	for e in inst.get("mods", []):
		var t := Stats.describe({str(e[1]): float(e[2])})
		if not t.is_empty():
			var tag := "" if e[4] == "u" else ("  (%s T%d)" % ["prefix" if e[4] == "p" else "suffix", int(e[3]) + 1])
			var st := str(e[1])
			if st.begins_with("dmg:"):
				for c in Classes.ELEMENTS:
					if st.get_slice(":", 1) in Classes.info(c)["skills"]:
						tag += "  [%s skill]" % Classes.info(c)["name"]
			out.append([t[0] + tag, Color(0.55, 0.7, 1.0) if e[4] != "u" else Color(1.0, 0.7, 0.35)])
	var u := int(inst.get("upg", 0))
	if u > 0 and damage(inst) == 0 and defense(inst) == 0:
		out.append(["+%d max life (upgrade +%d)" % [3 * u, u], Color(0.7, 1.0, 0.7)])
	if inst.get("rarity") == "unique":
		out.append([str(Items.UNIQUES.get(str(inst.get("uniq", "")), {}).get("flavour", "")), Color(0.85, 0.5, 0.2)])
	var req := req_level(inst)
	out.append(["Requires level %d" % req, Color(1, 0.45, 0.4) if level < req else Color(0.7, 0.7, 0.75)])
	var cn := Items.class_note(base)
	if cn != "":
		out.append([cn, Color(1, 0.45, 0.4) if cls != "" and not Items.can_use(base, cls) else Color(0.7, 0.7, 0.75)])
	out.append(["Sells for %d gold" % sell_price(inst), Color(0.85, 0.75, 0.4)])
	return out


## Comparison lines (this item vs the equipped one): stat differences, green = better.
static func compare(inst: Dictionary, equipped: Dictionary) -> Array:
	var out: Array = []
	var a := mods(inst)
	var b := mods(equipped)
	a["_damage"] = damage(inst)
	b["_damage"] = damage(equipped)
	a["_defense"] = defense(inst)
	b["_defense"] = defense(equipped)
	var keys := {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	var ks := keys.keys()
	ks.sort()
	for k in ks:
		var d := float(a.get(k, 0.0)) - float(b.get(k, 0.0))
		if absf(d) < 0.001:
			continue
		var label := ""
		if k == "_damage":
			label = "%+d damage" % roundi(d)
		elif k == "_defense":
			label = "%+d defense" % roundi(d)
		else:
			var t := Stats.describe({k: absf(d)})
			if t.is_empty():
				continue
			label = ("+" if d > 0 else "-") + str(t[0]).trim_prefix("+")
		var worse: bool = d < 0
		if k in ["dmg_taken_pct"]:
			worse = d < 0
		out.append([label, Color(1, 0.45, 0.4) if worse else Color(0.5, 1, 0.5)])
	if out.is_empty():
		out.append(["(no difference)", Color(0.7, 0.7, 0.75)])
	return out
