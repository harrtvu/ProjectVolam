## Martial Forms data (preloaded by consumers; no class_name for stale .godot caches).
## Martial Forms: Vo Lam Truyen Ky combo routes + Path of Exile support links.
##
## Each class has two Forms (chiêu thức / lộ tuyến). An active Form:
## * defines a combo sequence of skill slots (Vo Lam: cast in order for a Finisher)
## * opens 1-2 Support Link sockets (PoE: gem-like modifiers on every skill)
##
## Support mods are generic {stat_key: value} dictionaries that Stats / Talents.skill_def_m
## already understand, so combat code never special-cases Forms beyond combo + lifetap.
## Client and server share these pure functions.

const COMBO_WINDOW := 5.0       # seconds to continue the next step of a combo
const FINISHER_DURATION := 5.0  # seconds the finisher damage buff lasts
const MAX_LINKS := 2

## Shared PoE-style support link pool. Mods use the same keys as passives / gear.
const SUPPORTS := {
	"added_dmg": {"name": "Added Firepower", "viet": "Gia Lực",
		"desc": "+25% elemental (skill) damage", "mods": {"ele_dmg_pct": 25}, "min_level": 1},
	"faster_cast": {"name": "Swift Forms", "viet": "Tật Phong",
		"desc": "+20% cast speed (cooldowns recover faster)", "mods": {"cast_speed": 20}, "min_level": 1},
	"iron_will": {"name": "Iron Will", "viet": "Thiết Chí",
		"desc": "+15% attack, +8 defense", "mods": {"atk_pct": 15, "def_flat": 8}, "min_level": 1},
	"greater_aoe": {"name": "Expanding Force", "viet": "Bành Trướng",
		"desc": "+30% skill area of effect", "mods": {"aoe_pct": 30}, "min_level": 3},
	"venom": {"name": "Venom Coating", "viet": "Độc Phong",
		"desc": "+40% poison damage, poisons last +1.5 s", "mods": {"dot_poison": 40, "dur_poison": 1.5}, "min_level": 3},
	"combust": {"name": "Combustion", "viet": "Bạo Nhiên",
		"desc": "+40% burn damage", "mods": {"dot_burn": 40}, "min_level": 3},
	"lifetap": {"name": "Blood Pact Link", "viet": "Huyết Khế",
		"desc": "Skills cost 8% of max life instead of mana; +15% skill damage",
		"mods": {"flag:lifetap": 1, "ele_dmg_pct": 15}, "min_level": 6},
	"leech": {"name": "Soul Siphon", "viet": "Hấp Hồn",
		"desc": "3% of damage leeched as life, 2% as mana", "mods": {"life_leech": 3, "mana_leech": 2}, "min_level": 6},
	"fortify": {"name": "Mountain Guard", "viet": "Sơn Thủ",
		"desc": "+20% max life, 10% less damage taken", "mods": {"hp_pct": 20, "dmg_taken_pct": 10}, "min_level": 6},
	"culling": {"name": "Culling Strike", "viet": "Trảm Quyết",
		"desc": "+12% critical chance, +25% critical damage", "mods": {"crit": 12, "crit_dmg": 25}, "min_level": 10},
}

## Per-class Martial Forms. combo = skill slot indices (0-3) in order.
## finisher_dmg = % skill damage while the finisher buff is up.
## links = support sockets. unlock = character level required.
const FORMS := {
	"metal": [
		{"id": "blade_dance", "name": "Blade Dance", "viet": "Kiếm Vũ",
			"desc": "Whirl into a dash, whirl again, finish with Thousand Cuts.",
			"combo": [0, 1, 0, 3], "finisher_dmg": 35, "links": 1, "unlock": 1,
			"suggest": ["greater_aoe", "added_dmg"],
			"playstyle": "Vo Lam melee rhythm: clear with Whirl, gap-close, Whirl, execute."},
		{"id": "death_mark_form", "name": "Death Mark Form", "viet": "Tử Ấn",
			"desc": "Pierce in, Focus, then Thousand Cuts - the assassin's route.",
			"combo": [1, 2, 3], "finisher_dmg": 50, "links": 2, "unlock": 6,
			"suggest": ["culling", "faster_cast"],
			"playstyle": "PoE single-target burst: set up crits, then dump the finisher."},
	],
	"wood": [
		{"id": "thorn_path", "name": "Thorn Path", "viet": "Gai Lộ",
			"desc": "Thorn, Roots, Thorn, Bloom - poison the field, then detonate.",
			"combo": [0, 2, 0, 3], "finisher_dmg": 30, "links": 1, "unlock": 1,
			"suggest": ["venom", "added_dmg"],
			"playstyle": "Vo Lam DoT cadence: apply, root, re-apply, bloom."},
		{"id": "grove_heart_form", "name": "Grove Heart Form", "viet": "Lâm Tâm",
			"desc": "Regrowth, Roots, Bloom - survive, lock, then plague.",
			"combo": [1, 2, 3], "finisher_dmg": 40, "links": 2, "unlock": 6,
			"suggest": ["venom", "fortify"],
			"playstyle": "PoE sustain mapping: heal through packs while poison ticks."},
	],
	"water": [
		{"id": "frost_tide", "name": "Frost Tide", "viet": "Sương Triều",
			"desc": "Shard, Nova, Shard, Wave - slow, freeze, finish the line.",
			"combo": [0, 2, 0, 3], "finisher_dmg": 35, "links": 1, "unlock": 1,
			"suggest": ["faster_cast", "greater_aoe"],
			"playstyle": "Vo Lam control chain: poke, freeze, poke, tidal clear."},
		{"id": "tideweaver", "name": "Tideweaver", "viet": "Triều Chức",
			"desc": "Rain, Nova, Wave - mend allies, freeze, crash through.",
			"combo": [1, 2, 3], "finisher_dmg": 45, "links": 2, "unlock": 6,
			"suggest": ["greater_aoe", "leech"],
			"playstyle": "PoE support/clear hybrid: heal window into a big Wave."},
	],
	"fire": [
		{"id": "ember_cycle", "name": "Ember Cycle", "viet": "Tàn Luân",
			"desc": "Fireball, Burst, Fireball, Meteor - stack burns into a crater.",
			"combo": [0, 1, 0, 2], "finisher_dmg": 40, "links": 1, "unlock": 1,
			"suggest": ["combust", "added_dmg"],
			"playstyle": "Vo Lam caster cadence: poke, erupt, poke, skyfall."},
		{"id": "inferno_form", "name": "Inferno Form", "viet": "Hỏa Ngục",
			"desc": "Burst, Meteor, Inferno - everything burns at once.",
			"combo": [1, 2, 3], "finisher_dmg": 55, "links": 2, "unlock": 6,
			"suggest": ["combust", "greater_aoe"],
			"playstyle": "PoE screen-clear: AoE into delayed slam into ring of bolts."},
	],
	"earth": [
		{"id": "stone_march", "name": "Stone March", "viet": "Thạch Hành",
			"desc": "Slam, Stoneskin, Slam, Quake - armour up, then tremors.",
			"combo": [0, 1, 0, 3], "finisher_dmg": 30, "links": 1, "unlock": 1,
			"suggest": ["iron_will", "greater_aoe"],
			"playstyle": "Vo Lam tank rhythm: stun, shield, stun, earthquake."},
		{"id": "mountain_form", "name": "Mountain Form", "viet": "Sơn Thế",
			"desc": "Taunt, Stoneskin, Quake - pull the pack and bury it.",
			"combo": [2, 1, 3], "finisher_dmg": 40, "links": 2, "unlock": 6,
			"suggest": ["fortify", "iron_will"],
			"playstyle": "PoE juggernaut: grab aggro, layer defence, slam the pack."},
	],
}


static func for_class(cls: String) -> Array:
	return FORMS.get(cls, FORMS["metal"])


static func form(cls: String, id: String) -> Dictionary:
	for f in for_class(cls):
		if str(f["id"]) == id:
			return f
	return {}


static func default_form_id(cls: String) -> String:
	var list := for_class(cls)
	return str(list[0]["id"]) if not list.is_empty() else ""


static func support(id: String) -> Dictionary:
	return SUPPORTS.get(id, {})


static func support_ids() -> Array:
	var ids: Array = SUPPORTS.keys()
	ids.sort()
	return ids


## Aggregated mods from the active Form's support links (empty if unknown form / empty sockets).
static func mods(cls: String, form_id: String, supports: Array) -> Dictionary:
	var f := form(cls, form_id)
	if f.is_empty():
		return {}
	var total := {}
	var slots := mini(int(f.get("links", 1)), MAX_LINKS)
	var seen := {}
	var n := 0
	for s in supports:
		var sid := str(s)
		if sid == "" or seen.has(sid) or not SUPPORTS.has(sid):
			continue
		seen[sid] = true
		Stats.add_into(total, SUPPORTS[sid]["mods"])
		n += 1
		if n >= slots:
			break
	return total


## Validate / repair a saved Form choice. Returns {form_id, supports}.
static func sanitize(cls: String, level: int, form_id: String, supports: Array) -> Dictionary:
	var f := form(cls, form_id)
	if f.is_empty() or level < int(f.get("unlock", 1)):
		form_id = default_form_id(cls)
		f = form(cls, form_id)
	var slots := mini(int(f.get("links", 1)), MAX_LINKS)
	var out: Array = []
	var seen := {}
	for s in supports:
		var sid := str(s)
		if sid == "" or seen.has(sid) or not SUPPORTS.has(sid):
			continue
		if level < int(SUPPORTS[sid].get("min_level", 1)):
			continue
		seen[sid] = true
		out.append(sid)
		if out.size() >= slots:
			break
	return {"form_id": form_id, "supports": out}


static func can_select_form(cls: String, level: int, form_id: String) -> String:
	var f := form(cls, form_id)
	if f.is_empty():
		return "unknown Martial Form"
	if level < int(f.get("unlock", 1)):
		return "%s unlocks at level %d" % [f["name"], int(f["unlock"])]
	return ""


static func can_set_support(cls: String, level: int, form_id: String, supports: Array, slot: int, support_id: String) -> String:
	var f := form(cls, form_id)
	if f.is_empty():
		return "no Martial Form selected"
	var links := mini(int(f.get("links", 1)), MAX_LINKS)
	if slot < 0 or slot >= links:
		return "that Form only has %d support link(s)" % links
	if support_id == "":
		return ""   # clearing a socket is always fine
	if not SUPPORTS.has(support_id):
		return "unknown support link"
	var sp: Dictionary = SUPPORTS[support_id]
	if level < int(sp.get("min_level", 1)):
		return "%s unlocks at level %d" % [sp["name"], int(sp["min_level"])]
	for i in supports.size():
		if i != slot and str(supports[i]) == support_id:
			return "that support is already linked"
	return ""


## Human-readable combo like "1 → 2 → 1 → 4" with skill names.
static func combo_label(cls: String, form_id: String) -> String:
	var f := form(cls, form_id)
	if f.is_empty():
		return ""
	var parts: Array = []
	for slot in f["combo"]:
		var sid := Classes.skill_id(cls, int(slot))
		var nm: String = str(Classes.SKILLS[sid]["name"]) if sid != "" and Classes.SKILLS.has(sid) else ("Skill %d" % (int(slot) + 1))
		parts.append("%d:%s" % [int(slot) + 1, nm])
	return " → ".join(parts)


## After a successful skill cast: advance / reset the combo. Returns an event dict for logging/UI.
## event kinds: "advance" | "reset" | "finisher" | "ignore"
static func on_cast(p: Node, slot: int) -> Dictionary:
	var f := form(p.class_id, p.form_id)
	if f.is_empty():
		return {"kind": "ignore"}
	var route: Array = f["combo"]
	if route.is_empty():
		return {"kind": "ignore"}
	# window expired: start fresh from this cast if it matches step 0
	if p.combo_t <= 0.0 and p.combo_step > 0:
		p.combo_step = 0
	var expect := int(route[p.combo_step])
	if slot != expect:
		# wrong skill: restart if this cast is the first step, else reset
		if slot == int(route[0]):
			p.combo_step = 1
			p.combo_t = COMBO_WINDOW
			return {"kind": "reset", "step": p.combo_step, "need": int(route[0]) + 1}
		p.combo_step = 0
		p.combo_t = 0.0
		return {"kind": "reset", "step": 0, "need": int(route[0]) + 1}
	p.combo_step += 1
	if p.combo_step >= route.size():
		p.combo_step = 0
		p.combo_t = 0.0
		p.finisher_t = FINISHER_DURATION
		p.finisher_dmg = float(f.get("finisher_dmg", 30))
		return {"kind": "finisher", "dmg": p.finisher_dmg, "name": str(f["name"])}
	p.combo_t = COMBO_WINDOW
	return {"kind": "advance", "step": p.combo_step, "of": route.size(), "next": int(route[p.combo_step]) + 1}


static func describe_supports(supports: Array) -> Array:
	var out: Array = []
	for s in supports:
		var sp := support(str(s))
		if not sp.is_empty():
			out.append("%s (%s)" % [sp["name"], sp["desc"]])
	return out


## Suggested support ids for a Form (filtered to ones the player can use at `level`).
static func suggested(cls: String, form_id: String, level: int) -> Array:
	var f := form(cls, form_id)
	if f.is_empty():
		return []
	var out: Array = []
	for s in f.get("suggest", []):
		var sid := str(s)
		if SUPPORTS.has(sid) and level >= int(SUPPORTS[sid].get("min_level", 1)):
			out.append(sid)
	return out
