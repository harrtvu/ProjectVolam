class_name GM
## Game Master chat commands for faster testing.
## Enabled for accounts whose name is in Main.gm_names (defaults: gm, gamemaster, admin)
## plus any --gm=Name1,Name2 flags. Hideout logout still works normally.
##
## Commands (type in chat):
##   /gm                 help
##   /gm gold [n]        add gold (default 10000)
##   /gm level <n>       set level 1..50
##   /gm xp <n>          grant XP
##   /gm heal            full HP / mana
##   /gm god             toggle invulnerability
##   /gm item <base> [rarity] [ilvl]   put gear in bag
##   /gm unique <id>     put a unique in bag
##   /gm stack <id> [n]  potions / orbs / materials
##   /gm ticket [theme] [tier] [rarity]   dungeon ticket
##   /gm kit             testing kit (gold, orbs, potions, tickets)
##   /gm warp <zone> [x,y]   teleport (zone: meadow/forest/crypt/frost)
##   /gm kill [r]        kill monsters in radius (default 400)
##   /gm clearbag        destroy every bag item
##   /gm atlas           mark early atlas nodes complete (+ points)

const HELP := """GM commands:
/gm gold [n]   /gm level <n>   /gm xp <n>   /gm heal   /gm god
/gm item <base> [normal|magic|rare] [ilvl]
/gm unique <id>   /gm stack <id> [n]   /gm ticket [theme] [tier] [rarity]
/gm kit   /gm warp <zone> [x,y]   /gm kill [radius]   /gm clearbag   /gm atlas
Bases e.g. iron_sword chain_mail lich_staff. Themes: wood water earth fire metal."""


## True if this player's account name is on the server's GM list.
static func is_gm(main: Node, p: Node) -> bool:
	if main == null or p == null:
		return false
	var key := str(p.account_key).to_lower()
	var names: Dictionary = main.gm_names
	if names.has(key):
		return true
	# display name fallback (solo profiles sometimes key differently)
	return names.has(str(p.display_name).to_lower())


## Server: handle a /gm … chat line. Returns true if it was a GM command (consumed).
static func chat_command(main: Node, p: Node, text: String) -> bool:
	var raw := text.strip_edges()
	var low := raw.to_lower()
	if not (low == "/gm" or low.begins_with("/gm ")):
		return false
	if not is_gm(main, p):
		p.notify("You are not a Game Master. Use account name 'gm' (or start the server with --gm=YourName).", true)
		return true
	var parts: PackedStringArray = raw.split(" ", false)
	var sub := parts[1].to_lower() if parts.size() >= 2 else "help"
	match sub:
		"help", "?":
			p.notify(HELP, true)
		"gold":
			_gold(main, p, parts)
		"level", "lv":
			_level(main, p, parts)
		"xp":
			_xp(main, p, parts)
		"heal":
			p.hp = p.max_hp
			p.mp = p.max_mp
			p.notify("GM: fully healed (%d HP, %d MP)." % [p.hp, p.mp], true)
		"god":
			p.gm_god = not bool(p.gm_god)
			p.notify("GM: god mode %s." % ("ON (invulnerable)" if p.gm_god else "OFF"), true)
			main._log("[gm] %s god mode %s" % [p.display_name, "on" if p.gm_god else "off"])
		"item":
			_item(main, p, parts)
		"unique":
			_unique(main, p, parts)
		"stack":
			_stack(main, p, parts)
		"ticket":
			_ticket(main, p, parts)
		"kit":
			_kit(main, p)
		"warp", "tp":
			_warp(main, p, parts)
		"kill":
			_kill(main, p, parts)
		"clearbag", "clear":
			_clearbag(main, p)
		"atlas":
			_atlas(main, p)
		_:
			p.notify("Unknown GM command '%s'. Type /gm for help." % sub, true)
	return true


static func _gold(main: Node, p: Node, parts: PackedStringArray) -> void:
	var n := 10000
	if parts.size() >= 3:
		n = clampi(int(parts[2]), 0, 9999999)
	p.server_give("gold", n)
	p.notify("GM: +%d gold (now %d)." % [n, p.gold], true)
	main._log("[gm] %s +%d gold -> %d" % [p.display_name, n, p.gold])


static func _level(main: Node, p: Node, parts: PackedStringArray) -> void:
	if parts.size() < 3:
		p.notify("Usage: /gm level <1-50>", true)
		return
	var lv := clampi(int(parts[2]), 1, p.MAX_LEVEL)
	p.level = lv
	p.xp = 0
	p.recalc_stats()
	p.hp = p.max_hp
	p.mp = p.max_mp
	p.push_form()
	p.notify("GM: level set to %d." % lv, true)
	main._log("[gm] %s level -> %d" % [p.display_name, lv])
	if main.parties:
		main.parties.on_member_changed(p.account_key)


static func _xp(main: Node, p: Node, parts: PackedStringArray) -> void:
	if parts.size() < 3:
		p.notify("Usage: /gm xp <amount>", true)
		return
	var n := clampi(int(parts[2]), 1, 1000000)
	p.gain_xp(n, "gm")
	p.notify("GM: +%d XP." % n, true)
	main._log("[gm] %s +%d XP" % [p.display_name, n])


static func _bag_space(p: Node) -> bool:
	if p.bag_full():
		p.notify("GM: bag is full (%d/%d)." % [p.bag_used(), Items.BAG_SIZE], true)
		return false
	return true


static func _item(main: Node, p: Node, parts: PackedStringArray) -> void:
	if parts.size() < 3:
		p.notify("Usage: /gm item <base> [normal|magic|rare] [ilvl]", true)
		return
	var base := parts[2].to_lower()
	if not Items.BASES.has(base) or str(Items.BASES[base].get("slot", "")) == "ticket":
		p.notify("GM: unknown gear base '%s'." % base, true)
		return
	if not _bag_space(p):
		return
	var rarity := "rare"
	var ilvl := maxi(p.level, int(Items.BASES[base].get("lvl", 1)))
	if parts.size() >= 4 and parts[3].to_lower() in Gear.RARITIES:
		rarity = parts[3].to_lower()
	if parts.size() >= 5:
		ilvl = clampi(int(parts[4]), 1, 100)
	elif parts.size() >= 4 and parts[3].is_valid_int():
		ilvl = clampi(int(parts[3]), 1, 100)
	if rarity == "unique":
		p.notify("GM: use /gm unique <id> for uniques.", true)
		return
	var inst: Dictionary = Gear.make(base, rarity, ilvl, main.rng, p.class_id)
	p.bag.append(inst)
	p.push_inventory()
	p.notify("GM: spawned %s." % Gear.summary(inst), true)
	main._log("[gm] %s item %s" % [p.display_name, Gear.summary(inst)])


static func _unique(main: Node, p: Node, parts: PackedStringArray) -> void:
	if parts.size() < 3:
		p.notify("Usage: /gm unique <id>  (e.g. gold_seeker, frostbrand, venom_dagger)", true)
		return
	var uid := parts[2].to_lower()
	if not Items.UNIQUES.has(uid):
		p.notify("GM: unknown unique '%s'. Try: %s" % [uid, ", ".join(Items.UNIQUES.keys().slice(0, 8))], true)
		return
	if not _bag_space(p):
		return
	var ilvl := maxi(p.level, int(Items.UNIQUES[uid].get("lvl", 1)))
	var inst: Dictionary = Gear.make_unique(uid, ilvl, main.rng)
	p.bag.append(inst)
	p.push_inventory()
	p.notify("GM: spawned unique %s." % Gear.summary(inst), true)
	main._log("[gm] %s unique %s" % [p.display_name, uid])


static func _stack(main: Node, p: Node, parts: PackedStringArray) -> void:
	if parts.size() < 3:
		p.notify("Usage: /gm stack <id> [n]  (health_potion, enhance_stone, orb_chaos, …)", true)
		return
	var id := parts[2].to_lower()
	if id == "gold":
		_gold(main, p, parts)
		return
	if not Items.DB.has(id) or id == "gold":
		p.notify("GM: unknown stackable '%s'." % id, true)
		return
	var n := 20
	if parts.size() >= 4:
		n = clampi(int(parts[3]), 1, 9999)
	p.server_give(id, n)
	p.notify("GM: +%d %s." % [n, Items.info(id)["name"]], true)
	main._log("[gm] %s stack %s x%d" % [p.display_name, id, n])


static func _ticket(main: Node, p: Node, parts: PackedStringArray) -> void:
	if not _bag_space(p):
		return
	var theme := "fire"
	var tier := 2
	var rarity := "magic"
	if parts.size() >= 3 and parts[2].to_lower() in ["wood", "water", "earth", "fire", "metal"]:
		theme = parts[2].to_lower()
	if parts.size() >= 4:
		tier = clampi(int(parts[3]), 1, 10)
	if parts.size() >= 5 and parts[4].to_lower() in ["normal", "magic", "rare"]:
		rarity = parts[4].to_lower()
	var inst: Dictionary = Dungeons.make_ticket(theme, tier, rarity, main.rng)
	p.bag.append(inst)
	p.push_inventory()
	p.notify("GM: ticket %s." % Gear.summary(inst), true)
	main._log("[gm] %s ticket %s T%d %s" % [p.display_name, theme, tier, rarity])


static func _kit(main: Node, p: Node) -> void:
	p.server_give("gold", 25000)
	p.server_give("health_potion", 30)
	p.server_give("greater_potion", 20)
	for orb in Items.ORBS:
		p.server_give(orb, 20 if orb == "enhance_stone" else 10)
	var given: Array = []
	for spec in [
		["iron_sword", "rare", 12], ["chain_mail", "rare", 12], ["lich_staff", "rare", 13],
		["leather_boots", "magic", 8], ["jade_amulet", "rare", 10],
	]:
		if p.bag_full():
			break
		var inst: Dictionary = Gear.make(str(spec[0]), str(spec[1]), int(spec[2]), main.rng, p.class_id)
		p.bag.append(inst)
		given.append(Gear.summary(inst))
	if not p.bag_full():
		p.bag.append(Dungeons.make_ticket("fire", 2, "rare", main.rng))
	if not p.bag_full():
		p.bag.append(Gear.make_unique("gold_seeker", maxi(3, p.level), main.rng))
	p.push_inventory()
	if p.level < 20:
		p.level = 20
		p.xp = 0
		p.recalc_stats()
		p.hp = p.max_hp
		p.mp = p.max_mp
		p.push_form()
	p.notify("GM: testing kit granted (gold, orbs, potions, gear, tickets). Level %d." % p.level, true)
	main._log("[gm] %s kit (%s)" % [p.display_name, ", ".join(given)])


static func _warp(main: Node, p: Node, parts: PackedStringArray) -> void:
	if parts.size() < 3:
		p.notify("Usage: /gm warp <meadow|forest|crypt|frost> [x,y]", true)
		return
	var zid := parts[2].to_lower()
	if not Zones.DB.has(zid):
		p.notify("GM: unknown zone '%s'." % zid, true)
		return
	var cell: Vector2i = Zones.info(zid)["respawn"]
	if parts.size() >= 4:
		var xy: PackedStringArray = parts[3].split(",")
		if xy.size() == 2:
			cell = Vector2i(int(xy[0]), int(xy[1]))
	var z: Node = main.zones[zid]
	if not z.map.is_walkable(cell):
		cell = z.info["respawn"]
	var who := str(p.display_name)
	main.transfer_player(p, zid, cell)
	# transfer frees the old node — notify via system log only
	main._log("[gm] %s warped to %s @ %s" % [who, zid, cell])
	main.broadcast_system("GM %s warped to %s." % [who, Zones.info(zid)["name"]])


static func _kill(main: Node, p: Node, parts: PackedStringArray) -> void:
	var r := 400.0
	if parts.size() >= 3:
		r = clampf(float(parts[2]), 50.0, 5000.0)
	if p.zone == null:
		return
	var n := 0
	for m in p.zone.monsters_root.get_children():
		if not m.alive:
			continue
		if m.position.distance_to(p.position) <= r:
			m.take_damage(999999, p, {"crit": true, "skill": "GM Smite"})
			n += 1
	p.notify("GM: smote %d monster(s) within %.0f px." % [n, r], true)
	main._log("[gm] %s kill r=%.0f -> %d" % [p.display_name, r, n])


static func _clearbag(main: Node, p: Node) -> void:
	var n: int = p.bag.size()
	p.bag.clear()
	p.push_inventory()
	p.notify("GM: cleared %d bag item(s)." % n, true)
	main._log("[gm] %s clearbag (%d)" % [p.display_name, n])


static func _atlas(main: Node, p: Node) -> void:
	var a: Dictionary = p.atlas
	var done: Dictionary = a.get("done", {})
	# Unlock the first two tiers of every theme so merchant tickets open up.
	for th in ["wood", "water", "earth", "fire", "metal"]:
		for t in [1, 2]:
			var nid := "%s:%d" % [th, t]
			done[nid] = maxi(1, int(done.get(nid, 0)))
	a["done"] = done
	p.atlas = Atlas.sanitize(a)
	p.notify("GM: atlas nodes T1–T2 unlocked for all themes (%d points earned)." % Atlas.points_earned(p.atlas), true)
	main._log("[gm] %s atlas bootstrap" % p.display_name)
