class_name Stats
## Central stat / modifier aggregation.
##
## Every source of bonuses (talents today, gear affixes, set bonuses, buffs or
## map modifiers later) is just a Dictionary {stat_key: value}. Stats.gather()
## sums all sources for a character; the result (player.tmods) is the ONE place
## combat, loot and the UI read bonuses from. To add gear affixes, put a "mods"
## dictionary on an item (see items.gd: boss weapons already have one) or roll
## one per item instance later; nothing else needs to change.
##
## Stat keys are generic (no talent-specific names) so items can use them too:
##   life_pct mana_pct* atk_pct def_flat crit crit_dmg speed_pct mp_regen_pct ...
##   (* kept as hp_pct / mp_pct for save compatibility)
##   item_rarity item_quantity gold_find          -> loot / farming
##   life_leech mana_leech attack_speed cast_speed -> combat tempo
##   dmg_vs:<element>                             -> damage vs Metal/Wood/Water/Fire/Earth monsters
##   dmg:<skill> cd:<skill> radius:<skill> ...    -> skill modifiers (see talents.gd)

## key -> [label, suffix]; used to describe bonuses in tooltips / character sheet
const LABELS := {
	"hp_pct": ["max life", "%"], "mp_pct": ["max mana", "%"], "atk_pct": ["attack", "%"],
	"def_flat": ["defense", ""], "crit": ["critical chance", "%"], "crit_dmg": ["critical damage", "%"],
	"speed_pct": ["movement speed", "%"], "mp_regen_pct": ["mana regeneration", "%"],
	"heal_pct": ["healing done", "%"], "cost_pct": ["skill cost reduction", "%"],
	"dmg_taken_pct": ["damage taken reduction", "%"], "reflect": ["melee damage reflected", "%"],
	"vs_slowed": ["damage vs slowed/frozen", "%"], "mp_on_hit": ["mana per basic hit", ""],
	"dot_poison": ["poison damage", "%"], "dot_burn": ["burn damage", "%"],
	"dur_poison": ["poison duration", " s"], "slow_pct": ["slow strength", "%"], "dur_slow": ["slow duration", " s"],
	"item_rarity": ["item rarity", "%"], "item_quantity": ["item quantity", "%"], "gold_find": ["gold found", "%"],
	"life_leech": ["damage leeched as life", "%"], "mana_leech": ["damage leeched as mana", "%"],
	"attack_speed": ["attack speed", "%"], "cast_speed": ["cast speed (cooldown recovery)", "%"],
	"life_flat": ["maximum life", ""], "mana_flat": ["maximum mana", ""], "dmg_flat": ["damage", ""],
	"ele_dmg_pct": ["elemental (skill) damage", "%"], "res_all": ["to all elemental resistances", "%"],
}


static func add_into(total: Dictionary, src: Dictionary) -> void:
	for k in src:
		total[k] = float(total.get(k, 0.0)) + float(src[k])


## All modifiers of a character: talents + equipped items' affixes.
static func gather(cls: String, talents: Dictionary, equipment: Dictionary) -> Dictionary:
	var total := {}
	add_into(total, Talents.mods(cls, talents))
	for slot in equipment:
		var inst = equipment[slot]
		if typeof(inst) == TYPE_DICTIONARY and not inst.is_empty():
			add_into(total, Gear.mods(inst))
	return total


static func label(key: String) -> String:
	if key.begins_with("res:"):
		return "%s resistance" % Classes.ELEMENT_INFO.get(key.get_slice(":", 1), {"name": "?"})["name"]
	if key.begins_with("dmg:") and Classes.SKILLS.has(key.get_slice(":", 1)):
		return "%s damage" % Classes.SKILLS[key.get_slice(":", 1)]["name"]
	if key.begins_with("dmg_vs:"):
		return "damage vs %s monsters" % Classes.ELEMENT_INFO.get(key.get_slice(":", 1), {"name": "?"})["name"]
	return str(LABELS.get(key, [key, ""])[0])


## Human-readable list of the generic (non skill-specific) bonuses.
static func describe(mods: Dictionary) -> Array:
	var out: Array = []
	var keys := mods.keys()
	keys.sort()
	for k in keys:
		var v := float(mods[k])
		var ks := str(k)
		var shown := not ks.contains(":") or ks.begins_with("dmg_vs:") or ks.begins_with("res:") or (ks.begins_with("dmg:") and Classes.SKILLS.has(ks.get_slice(":", 1)))
		if v == 0.0 or not shown:
			continue
		var suffix: String = "%" if ks.contains(":") else str(LABELS.get(k, ["", ""])[1])
		var num := ("%d" % v) if is_equal_approx(v, roundf(v)) else ("%.1f" % v)
		out.append("%s%s%s %s" % ["+" if v > 0 else "", num, suffix, label(k)])
	return out
