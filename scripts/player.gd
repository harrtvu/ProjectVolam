extends CharacterBody2D
## A player character.
## Everything important is SERVER-AUTHORITATIVE: the owning client only sends
## input and requests (attack, pick up, use, equip); the server simulates
## movement, combat, XP, inventory and replicates the results.

signal inventory_changed

const SPEED := 160.0
const RADIUS := 10.0
const ATTACK_RANGE := 56.0
const ATTACK_COOLDOWN := 0.35
const SWING_TIME := 0.2
const PICKUP_RANGE := 48.0
const BLACKSMITH_RANGE := 100.0
const RESPAWN_TIME := 4.0
const MAX_LEVEL := 50
const RANGED_BASIC_RANGE := 260.0
const CRIT_MULT := 1.75
# status_flags bits (replicated, for visuals)
const ST_SHIELD := 1
const ST_FOCUS := 2
const ST_REGROWTH := 4
const ST_FORTIFY := 8

var peer_id: int = 1
var display_name: String = "Player"
var account_key: String = ""     # server only
var hideout: Dictionary = Hideouts.default_layout()   # hideout layout (server-authoritative, mirrored to the owner)
var zone: Node = null            # the zone node this player lives in (set by the spawn function)

# ---- replicated to everyone (server -> clients)
var sync_pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: int = 30: set = _set_hp
var max_hp: int = 30
var level: int = 1: set = _set_level
var xp: int = 0
var xp_next: int = 20
var attack: int = 1
var defense: int = 0
var dead: bool = false
var class_id: String = "metal"   # set from spawn data, never changes for a character
var element: String = "metal"
var mp: int = 30
var max_mp: int = 30
var crit: float = 0.05
var move_speed: float = SPEED
var status_flags: int = 0

# ---- owner-only state (server keeps the truth, owner gets a copy via RPC)
var inventory: Dictionary = {}   # item_id -> count
var gold: int = 0
var equipment: Dictionary = {}     # slot -> gear instance ({} = empty), see Items.SLOTS
var bag: Array = []                # gear instances (inventory holds the stackables)
var stash: Array = []              # account stash at the blacksmith
var atlas: Dictionary = {"done": {}}   # dungeon completions {"done": {"wood:3": runs}} (see dungeons.gd)
var free_day := ""                     # date of the last free daily ticket
var run_info: Dictionary = {}          # (owner client) the open dungeon run, for the UI
var _drop_block_t := 0.0
var _bagfull_ms := -99999
var _rng := RandomNumberGenerator.new()   # server: every loot / crafting roll
var talents: Dictionary = {}     # talent id -> rank (server truth; owner gets a copy)
var tmods: Dictionary = {}       # Talents.mods() cache

var _input_dir := Vector2.ZERO        # server: latest input from owner
var _last_sent := Vector2(INF, INF)   # owner: last input sent
var _attack_cd := 0.0
var _swing_t := 0.0
var _respawn_t := 0.0
var _since_hit := 99.0
var _regen_t := 0.0
var _flash := 0.0
var _anim_t := 0.0
var _last_pos := Vector2.ZERO
var _portal_cd := 1.0
var _main: Node
var _sprite: Sprite2D
var _label: Label
var _char_tex: Texture2D
var _tomb_tex: Texture2D
# ---- server-side combat state
var _cooldowns := [0.0, 0.0, 0.0, 0.0]
var _mp_regen_t := 0.0
var _shield := 0
var _shield_t := 0.0
var _focus_t := 0.0
var _fortify_t := 0.0
var _hot_t := 0.0
var _hot_per_sec := 0.0
var _hot_acc := 0.0
var _pending: Array = []          # [[seconds_left, Callable], ...] delayed skill effects
var _deny_ms := {}                # reason -> last log time (rate limit)
var _shield_name := "Stone Skin"
var _phoenix_cd := 0.0
var _leech_hp := 0.0
var _leech_mp := 0.0
var _talent_log_ms := {}
# ---- owner-side skill cooldown display: slot -> [end_msec, total_sec]
var cd_client := {}


## Called by the spawn function (on server AND clients) before entering the tree.
func setup(id: int, pname: String, pos: Vector2, stats: Dictionary) -> void:
	class_id = str(stats.get("class", "metal"))
	if not Classes.exists(class_id):
		class_id = "metal"
	element = Classes.element_of(class_id)
	move_speed = float(Classes.info(class_id)["speed"])
	peer_id = id
	display_name = pname
	name = str(id)
	position = pos
	sync_pos = pos
	_last_pos = pos
	level = int(stats.get("level", 1))
	max_hp = int(stats.get("max_hp", 30))
	hp = int(stats.get("hp", max_hp))
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2   # players
	collision_mask = 1    # world (walls/water/trees)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

	_char_tex = load("res://assets/classes/%s_%d.png" % [class_id, absi(pname.to_lower().hash()) % 2])
	_tomb_tex = load("res://assets/tombstone.png")
	_sprite = Sprite2D.new()
	_sprite.texture = _char_tex
	_sprite.offset = Vector2(0, -12)
	add_child(_sprite)

	_label = Label.new()
	_label.name = "NameLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(160, 18)
	_label.position = Vector2(-80, -52)
	_label.z_index = 10
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Classes.color(element).lerp(Color.WHITE, 0.35))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_update_label()

	add_child(NetUtil.make_synchronizer(["sync_pos"],
		["facing", "hp", "max_hp", "level", "xp", "xp_next", "attack", "defense", "dead",
		 "mp", "max_mp", "crit", "status_flags", "move_speed"]))


func is_local() -> bool:
	return multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id()


func _ready() -> void:
	_main = get_node_or_null("/root/Main")
	_rng.randomize()
	if _main and int(_main.craft_seed) >= 0:   # tests: deterministic crafting / enhancement rolls
		_rng.seed = int(_main.craft_seed)
	if is_local():
		var cam := Camera2D.new()
		cam.name = "Camera"
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 8.0
		if zone:
			var size: Vector2i = zone.map.world_size_px()
			var origin: Vector2 = zone.global_position
			cam.limit_left = int(origin.x)
			cam.limit_top = int(origin.y)
			cam.limit_right = int(origin.x) + size.x
			cam.limit_bottom = int(origin.y) + size.y
		add_child(cam)
		cam.make_current()


func _set_hp(v: int) -> void:
	var diff := v - hp
	hp = v
	if diff < 0:
		_flash = 0.2
	if diff != 0 and _popups_ok() and not dead:
		NetUtil.popup(self, ("%+d" % diff), Color(1, 0.35, 0.35) if diff < 0 else Color(0.4, 1, 0.4))


func _set_level(v: int) -> void:
	var up := v > level
	level = v
	_update_label()
	if up and _popups_ok():
		NetUtil.popup(self, "LEVEL UP!", Color(1, 0.9, 0.3), -64.0)


func _update_label() -> void:
	if _label:
		_label.text = "%s  Lv %d" % [display_name, level]
		# element icon goes just left of the (centered) name
		var w := _label.get_theme_font("font").get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_icon_x = -w / 2.0 - 10.0


# ================================================================ simulation

func _physics_process(delta: float) -> void:
	if is_local():
		_handle_local_input()

	if multiplayer.is_server():
		_server_tick(delta)
	else:
		NetUtil.smooth_follow(self, sync_pos, delta)

	# visuals (all peers)
	var moving := position.distance_to(_last_pos) > 0.3
	_last_pos = position
	_anim_t = _anim_t + delta * 12.0 if moving else 0.0
	if _sprite:
		_sprite.texture = _tomb_tex if dead else _char_tex
		_sprite.position.y = -absf(sin(_anim_t)) * 3.0
		_sprite.rotation = sin(_anim_t) * 0.08
		if absf(facing.x) > 0.1:
			_sprite.flip_h = facing.x < 0.0
		_sprite.modulate = Color(1, 0.45, 0.45) if _flash > 0.0 else Color.WHITE
	if _flash > 0.0:
		_flash -= delta
	if _swing_t > 0.0:
		_swing_t -= delta
	queue_redraw()


func _server_tick(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_since_hit += delta
	if dead:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_server_respawn()
		sync_pos = position
		return
	_combat_tick(delta)
	velocity = _input_dir * move_speed
	move_and_slide()
	if _input_dir != Vector2.ZERO:
		facing = _input_dir.normalized()
	sync_pos = position
	# slow regeneration when out of combat
	if _since_hit > 6.0 and hp < max_hp and zone.dungeon_mod("map_no_regen") <= 0.0:
		_regen_t += delta
		if _regen_t >= 2.0:
			_regen_t = 0.0
			hp = mini(max_hp, hp + 1)
	# walk-over pickup (not right after dropping something on purpose)
	_drop_block_t = maxf(0.0, _drop_block_t - delta)
	if _drop_block_t <= 0.0:
		for p in zone.loot_root.get_children():
			if not p.is_queued_for_deletion() and p.position.distance_to(position) <= 20.0:
				_server_take_pickup(p)
	# zone exits
	_portal_cd = maxf(0.0, _portal_cd - delta)
	if _portal_cd <= 0.0:
		var portal: Dictionary = zone.portal_at(position)
		if not portal.is_empty() and _main:
			_portal_cd = 1.0
			_main.transfer_player.call_deferred(self, portal["to"], portal["arrive"])
		elif _main and _main.instances and not zone.map_portals.is_empty():
			var mp_: Dictionary = zone.map_portal_at(position)
			if not mp_.is_empty():
				_portal_cd = 1.5
				_main.instances.try_enter.call_deferred(self, str(mp_["id"]))


func _handle_local_input() -> void:
	var dir := Vector2.ZERO
	if _main and _main.menu_open():
		dir = Vector2.ZERO      # Esc menu open: no movement / skill input (the world may continue online)
	elif _main and _main.bot_mode:
		dir = _main.bot_dir
	elif not (_main and _main.chat_active):
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if Input.is_action_just_pressed("attack"):
			request_attack()
		if Input.is_action_just_pressed("pickup"):
			if near_blacksmith() and not _loot_nearby() and _main:
				_main.toggle_smith()
			elif near_map_device() and not _loot_nearby() and _main:
				_main.toggle_map_ui("device")
			elif near_merchant() and not _loot_nearby() and _main:
				_main.toggle_map_ui("merchant")
			elif near_broker() and not _loot_nearby() and _main:
				_main.toggle_market_ui()
			elif near_hideout_master() and not _loot_nearby() and _main:
				_main.toggle_hideout_ui()
			else:
				request_pickup()
		if Input.is_action_just_pressed("use_potion"):
			request_use(best_potion())
		for i in 4:
			var act := "skill_%d" % (i + 1)
			if Input.is_action_just_pressed(act):
				if is_ground_skill(i):
					_main.hold_slot = i      # aim with the preview, cast on release
				else:
					request_skill(i)
			elif Input.is_action_just_released(act) and _main.hold_slot == i:
				_main.hold_slot = -1
				request_skill(i)
	if dead:
		dir = Vector2.ZERO
	if dir != _last_sent:
		_last_sent = dir
		_send("input", dir)


## Picks a potion for quick-use: greater potion for big wounds, else the small one.
func best_potion() -> String:
	var missing := max_hp - hp
	if missing >= 30 and int(inventory.get("greater_potion", 0)) > 0:
		return "greater_potion"
	if int(inventory.get("health_potion", 0)) > 0:
		return "health_potion"
	return "greater_potion"


# ---- client helpers (send requests to the server)
func _send(action: String, arg: Variant = null) -> void:
	if _main and multiplayer.has_multiplayer_peer():
		_main.player_request.rpc_id(1, action, arg)

func request_attack() -> void:
	_send("attack", _main.target_request(self) if _main else {})

func request_use(item_id: String) -> void:
	_send("use", item_id)

func request_equip(uid: int, slot := "") -> void:
	_send("equip", {"uid": uid, "slot": slot})

func request_craft(orb: String, uid: int) -> void:
	_send("craft", {"orb": orb, "uid": uid})

func request_sell(uid: int) -> void:
	_send("sell", {"uid": uid})

func request_sell_stack(id: String) -> void:
	_send("sell", {"stack": id})

func request_drop(uid: int) -> void:
	_send("drop_item", {"uid": uid})

func request_destroy(uid: int) -> void:
	_send("destroy_item", {"uid": uid})

func request_stash(op: String, uid: int) -> void:
	_send("stash", {"op": op, "uid": uid})

func request_unequip(slot: String) -> void:
	_send("unequip", slot)

func _loot_nearby() -> bool:
	for p in zone.loot_root.get_children():
		if p.position.distance_to(position) <= PICKUP_RANGE:
			return true
	return false

func request_pickup() -> void:
	_send("pickup")

func request_skill(slot: int) -> void:
	var req: Dictionary = _main.target_request(self) if _main else {}
	if req.is_empty():
		_send("skill", slot)      # plain request: server auto-targets the nearest monster
	else:
		req["slot"] = slot
		_send("skill", req)


func request_talent(id: String) -> void:
	_send("talent", id)


func request_respec() -> void:
	_send("respec")


func request_refund(id: String) -> void:
	_send("refund", id)


func request_market(op: String, args := {}) -> void:
	var d: Dictionary = args.duplicate()
	d["op"] = op
	_send("market", d)


func request_hideout(op: String, args := {}) -> void:
	var d: Dictionary = args.duplicate()
	d["op"] = op
	_send("hideout", d)


func near_hideout_master() -> bool:
	return zone != null and zone.has_method("hideout_master_pos") and zone.hideout_master_pos() != Vector2.INF \
		and position.distance_to(zone.hideout_master_pos()) <= BLACKSMITH_RANGE


func request_dungeon(op: String, args := {}) -> void:
	var d: Dictionary = args.duplicate()
	d["op"] = op
	_send("dungeon", d)


## Skills that are aimed at a point on the ground (preview while the key is held).
func is_ground_skill(slot: int) -> bool:
	var sid := Classes.skill_id(class_id, slot)
	return sid != "" and str(Classes.SKILLS[sid]["kind"]) in ["aoe_target", "delayed_target"]


## Range ring + area / direction preview for a skill (drawn under the local player).
func _draw_preview(slot: int) -> void:
	var sid := Classes.skill_id(class_id, slot)
	if sid == "":
		return
	var sk := skill_def(sid)
	var col := Classes.color(element)
	var kind := str(sk["kind"])
	var rng := float(sk.get("range", sk.get("radius", 60.0)))
	if kind == "heal_area":
		rng = 300.0
	draw_arc(Vector2.ZERO, rng, 0.0, TAU, 64, Color(col, 0.55), 2.0)
	var m := get_local_mouse_position()
	if kind in ["aoe_target", "delayed_target"]:
		var at := m.limit_length(rng)
		var r := float(sk["radius"])
		draw_circle(at, r, Color(col, 0.22))
		draw_arc(at, r, 0.0, TAU, 40, Color(col.lerp(Color.WHITE, 0.4), 0.95), 2.5)
		draw_line(Vector2(0, -8), at, Color(col, 0.4), 1.5)
	elif kind in ["projectile", "dash"]:
		draw_line(Vector2(0, -8), Vector2(0, -8) + m.normalized() * rng, Color(col.lerp(Color.WHITE, 0.4), 0.8), 3.0)
	elif sk.has("radius"):
		draw_circle(Vector2.ZERO, float(sk["radius"]), Color(col, 0.18))


## Owner: seconds of cooldown left on a skill slot (for the HUD).
func cooldown_left(slot: int) -> float:
	if not cd_client.has(slot):
		return 0.0
	return maxf(0.0, (float(cd_client[slot][0]) - Time.get_ticks_msec()) / 1000.0)


func cooldown_total(slot: int) -> float:
	return float(cd_client[slot][1]) if cd_client.has(slot) else 1.0


# ================================================================ server logic

func _srv_log(msg: String) -> void:
	print("[%s] [SERVER] [%s] %s" % [Time.get_time_string_from_system(), zone.zone_id if zone else "?", msg])


static func xp_for_level(lv: int) -> int:
	return 20 * lv


func recalc_stats() -> void:
	max_hp = int(Classes.stat(class_id, "hp", level))
	max_mp = int(Classes.stat(class_id, "mp", level))
	attack = roundi(Classes.stat(class_id, "atk", level)) + Gear.damage(equipment.get("weapon", {}))
	defense = roundi(Classes.stat(class_id, "def", level))
	for slot in equipment:
		defense += Gear.defense(equipment[slot])
	crit = Classes.stat(class_id, "crit", level)
	move_speed = float(Classes.info(class_id)["speed"])
	# passives + gear affixes (one aggregated modifier dictionary)
	tmods = Stats.gather(class_id, talents, equipment)
	max_hp += roundi(tm("life_flat"))
	max_mp += roundi(tm("mana_flat"))
	attack += roundi(tm("dmg_flat"))
	max_hp = roundi(max_hp * (1.0 + tm("hp_pct") / 100.0))
	max_mp = roundi(max_mp * (1.0 + tm("mp_pct") / 100.0))
	attack = roundi(attack * (1.0 + tm("atk_pct") / 100.0))
	defense += roundi(tm("def_flat"))
	crit += tm("crit") / 100.0
	move_speed *= 1.0 + tm("speed_pct") / 100.0
	mp = mini(mp, max_mp)
	xp_next = xp_for_level(level)
	hp = mini(hp, max_hp)


## Server: load saved character data (or defaults for a new character).
func apply_character(c: Dictionary) -> void:
	level = clampi(int(c.get("level", 1)), 1, MAX_LEVEL)
	xp = maxi(0, int(c.get("xp", 0)))
	gold = maxi(0, int(c.get("gold", 0)))
	_load_items(c)
	atlas = Dungeons.sanitize_atlas(c.get("atlas", {}))
	if Atlas.is_legacy(c.get("atlas", {})):
		_srv_log("[atlas] %s: migrated old atlas grid %s -> atlas map nodes %s (remapped %s), %d atlas points granted for past completions" % [
			display_name, c["atlas"].get("done", {}), atlas["done"], atlas["migrated"], Atlas.points_earned(atlas)])
	free_day = str(c.get("free_day", ""))
	hideout = Hideouts.sanitize(c.get("hideout", {}))
	talents = {}
	var tl = c.get("talents", {})
	if typeof(tl) == TYPE_DICTIONARY:
		talents = Talents.sanitize(class_id, level, tl)
		if talents.size() != tl.size():   # (server only)
			_srv_log("%s: saved passives didn't fit the current web (old talent-tree save?) - %d of %d kept, points refunded" % [display_name, talents.size(), tl.size()])
	hp = 999999
	mp = 999999
	recalc_stats()
	hp = clampi(int(c.get("hp", max_hp)), 1, max_hp)
	mp = clampi(int(c.get("mp", max_mp)), 0, max_mp)
	var cds = c.get("_cd", null)   # carried over a zone transfer
	if typeof(cds) == TYPE_ARRAY and cds.size() == 4:
		for i in 4:
			_cooldowns[i] = float(cds[i])


## Items from a save: new format (instances) or the old one (plain ids) -> migrated to instances.
func _load_items(c: Dictionary) -> void:
	inventory = {}
	bag = []
	stash = []
	equipment = {}
	for sl in Items.SLOTS:
		equipment[sl] = {}
	var migrated: Array = []
	var inv = c.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		for k in inv:
			var id := str(k)
			var n := int(inv[k])
			if n <= 0:
				continue
			if Items.is_base(id):      # old save: gear stored as counts
				for i in n:
					bag.append(Gear.from_legacy(id, _rng))
					migrated.append(id)
			elif Items.DB.has(id) and id != "gold":
				inventory[id] = n
	for v in c.get("bag", []):
		var inst := Gear.sanitize(v)
		if not inst.is_empty():
			bag.append(inst)
	for v in c.get("stash", []):
		var inst := Gear.sanitize(v)
		if not inst.is_empty():
			stash.append(inst)
	var eq = c.get("equipment", {})
	if typeof(eq) == TYPE_DICTIONARY:
		for slot in eq:
			var v = eq[slot]
			var inst := {}
			var want := str(slot)
			if typeof(v) == TYPE_STRING:      # old save: {"weapon": "iron_sword", "armor": "wooden_shield"}
				if not Items.is_base(str(v)):
					continue
				inst = Gear.from_legacy(str(v), _rng)
				migrated.append(str(v))
				want = Items.slots_for(str(v))[0]
			else:
				inst = Gear.sanitize(v)
			if inst.is_empty():
				continue
			if want in Items.slots_for(str(inst["base"])) and Items.can_use(str(inst["base"]), class_id) and equipment[want].is_empty():
				equipment[want] = inst
			else:   # e.g. an old save wearing something this class can't use
				bag.append(inst)
	if not migrated.is_empty():   # (apply_character only runs on the server)
		_srv_log("%s: migrated %d old item(s) to gear instances: %s" % [display_name, migrated.size(), ", ".join(migrated)])


## Resistance to an element after caps (all-res included), in percent.
func resistance(el: String) -> float:
	if el == "":
		return 0.0
	var map_pen: float = zone.dungeon_mod("map_less_res") if zone and zone.has_method("dungeon_mod") else 0.0
	return clampf(tm("res:" + el) + tm("res_all") - map_pen, -100.0, Gear.RES_CAP)


func _res_line() -> String:
	var parts: Array = []
	for e in Gear.ELEMENTS:
		parts.append("%s %d%%" % [e, roundi(resistance(e))])
	return ", ".join(parts)


## Short, log-friendly equipment summary ("weapon=iron_sword(normal)...").
func equip_summary() -> String:
	var parts: Array = []
	for sl in Items.SLOTS:
		if not equipment.get(sl, {}).is_empty():
			parts.append("%s=%s(%s%s)" % [sl, equipment[sl]["base"], equipment[sl]["rarity"],
				(" +%d" % int(equipment[sl]["upg"])) if int(equipment[sl].get("upg", 0)) > 0 else ""])
	return "{%s}" % ", ".join(parts)


func _save_pos() -> Array:
	if zone and Zones.is_hideout(zone.zone_id):
		return [position.x, position.y]
	if zone and zone.is_dungeon() and _main:
		var p: Vector2 = _main.zones["meadow"].map.cell_pos(Zones.TOWN_ARRIVE)
		return [p.x, p.y]
	return [position.x, position.y]


func _save_zone() -> String:
	if zone == null or zone.is_dungeon():
		return "meadow"
	if Zones.is_hideout(zone.zone_id):
		return "hideout"
	return zone.zone_id


func to_character() -> Dictionary:
	return {
		"level": level, "xp": xp,
		"class": class_id,
		"hp": max_hp if dead else hp,
		"mp": mp,
		"pos": _save_pos(), "map_v": Zones.MAP_VERSION,   # positions are in big-map coordinates
		"zone": _save_zone(),   # never log back in inside a dungeon; "hideout" reopens your hideout
		"hideout": hideout.duplicate(true),
		"gold": gold, "inventory": inventory.duplicate(),
		"equipment": equipment.duplicate(true), "bag": bag.duplicate(true), "stash": stash.duplicate(true), "items_v": 2,
		"talents": talents.duplicate(),
		"atlas": atlas.duplicate(true), "free_day": free_day,
	}


func tm(key: String) -> float:
	return float(tmods.get(key, 0.0))


func crit_mult() -> float:
	return CRIT_MULT + tm("crit_dmg") / 100.0


## This character's version of a skill, with talents applied.
func skill_def(sid: String) -> Dictionary:
	return Talents.skill_def_m(tmods, sid)


func effective_defense() -> int:
	return roundi(defense * (1.5 if _fortify_t > 0.0 else 1.0))


## Server: incoming damage. `src_element` is the attacker's element (Wu Xing multiplier).
## Damage after the Wu Xing multiplier, elemental resistance (capped 75%), defense and % reduction.
func incoming_damage(amount: int, src_element: String) -> int:
	var emult := Classes.multiplier(src_element, element)
	var res := resistance(src_element)
	var dmg := maxi(1, roundi(amount * emult * (1.0 - res / 100.0)) - effective_defense())
	var reduce := tm("dmg_taken_pct") + (20.0 if tm("flag:grove_heart") > 0.0 and _hot_t > 0.0 else 0.0)
	if reduce > 0.0:
		dmg = maxi(1, roundi(dmg * (1.0 - reduce / 100.0)))
	return dmg


func server_take_damage(amount: int, source: String, src_element: String = "", attacker: Node = null) -> void:
	if dead:
		return
	var emult := Classes.multiplier(src_element, element)
	var res := resistance(src_element)
	var dmg := incoming_damage(amount, src_element)
	if attacker and is_instance_valid(attacker) and tm("reflect") > 0.0 and attacker.alive:
		var back := maxi(1, roundi(dmg * tm("reflect") / 100.0))
		attacker.take_damage(back, self, {"dot": true})
		_tlog("reflect", "%s's Thorns of Stone reflect %d damage to %s" % [display_name, back, attacker.display_name])
	_since_hit = 0.0
	var note := ""
	if emult != 1.0:
		note = " [%s x%.2f]" % [Classes.ELEMENT_INFO[src_element]["name"] + (">" if emult > 1.0 else "<") + Classes.ELEMENT_INFO[element]["name"], emult]
	if res != 0.0:
		note += " [%s res %d%%]" % [Classes.ELEMENT_INFO[src_element]["name"], roundi(res)]
	if _shield > 0:
		var absorbed := mini(_shield, dmg)
		_shield -= absorbed
		dmg -= absorbed
		_srv_log("%s's %s shield absorbs %d (%d left)" % [display_name, _shield_name, absorbed, _shield])
		if _shield <= 0:
			_shield_t = 0.0
			_shield_ended()
		if dmg <= 0:
			_update_status_flags()
			return
	hp = maxi(0, hp - dmg)
	_srv_log("%s took %d damage from %s (hp %d/%d)%s" % [display_name, dmg, source, hp, max_hp, note])
	if hp == 0 and tm("flag:phoenix") > 0.0 and _phoenix_cd <= 0.0:
		_phoenix_cd = 60.0
		hp = maxi(1, roundi(max_hp * 0.3))
		_srv_log("%s's Phoenix Heart triggers: survives at %d/%d HP and erupts!" % [display_name, hp, max_hp])
		var burst := skill_def("burst")
		SkillCaster.fx(self, "burst", position, float(burst["radius"]))
		for m in SkillCaster.monsters_in(self, position, float(burst["radius"])):
			hit_monster(m, float(burst["mult"]), burst)
		return
	if hp == 0:
		dead = true
		_respawn_t = RESPAWN_TIME
		_input_dir = Vector2.ZERO
		velocity = Vector2.ZERO
		_pending.clear()
		_hot_t = 0.0
		_srv_log("%s died (respawn in %.0fs)" % [display_name, RESPAWN_TIME])
		if _main:
			_main.broadcast_system("%s was defeated by %s!" % [display_name, source])


func _server_respawn() -> void:
	if zone and zone.is_dungeon() and _main and _main.instances:
		dead = false
		hp = max_hp
		mp = max_mp
		_since_hit = 99.0
		_main.instances.player_died.call_deferred(self)   # back to town; re-entering costs a portal
		return
	if zone:
		position = zone.map.spot_near(zone.info["respawn"], _main.rng if _main else RandomNumberGenerator.new())
	sync_pos = position
	dead = false
	hp = max_hp
	mp = max_mp
	_since_hit = 99.0
	_srv_log("%s respawned at spawn point %s" % [display_name, position.round()])


func server_add_xp(amount: int) -> void:
	if level >= MAX_LEVEL:
		return
	xp += amount
	_srv_log("%s gained %d XP (%d/%d)" % [display_name, amount, xp, xp_next])
	while xp >= xp_next and level < MAX_LEVEL:
		xp -= xp_next
		level += 1
		recalc_stats()
		hp = max_hp
		mp = max_mp
		for slot in 4:
			if Classes.skill_unlock_level(slot) == level:
				var sk: Dictionary = Classes.SKILLS[Classes.skill_id(class_id, slot)]
				_srv_log("%s unlocked skill %d: %s (level %d)" % [display_name, slot + 1, sk["name"], level])
				notify("New skill unlocked: [%d] %s" % [slot + 1, sk["name"]], true)
		_srv_log("%s reached level %d (max hp %d, attack %d)" % [display_name, level, max_hp, attack])
		if _main:
			_main.broadcast_system("%s reached level %d!" % [display_name, level])


func server_give(item_id: String, count: int) -> void:
	if item_id == "gold":
		gold += roundi(count)
	else:
		inventory[item_id] = int(inventory.get(item_id, 0)) + count
	push_inventory()


## Can this pickup go in the bag? (gold always; a stack we already have always)
func can_take_pickup(p: Node) -> bool:
	if p.item_id == "gold" or (p.inst.is_empty() and inventory.has(p.item_id)):
		return true
	return not bag_full()


func _server_take_pickup(p: Node) -> void:
	if not can_take_pickup(p):
		var now := Time.get_ticks_msec()
		if now - _bagfull_ms > 3000:
			_bagfull_ms = now
			_srv_log("%s can't pick up %s: bag full (%d/%d)" % [display_name, p.label_text(), bag_used(), Items.BAG_SIZE])
			notify("Bag full (%d/%d)" % [bag_used(), Items.BAG_SIZE])
		return
	if not p.inst.is_empty():
		bag.append(p.inst)
		_srv_log("%s picked up %s" % [display_name, Gear.summary(p.inst)])
		push_inventory()
	else:
		server_give(p.item_id, p.amount)
		_srv_log("%s picked up %d x %s" % [display_name, p.amount, p.item_id])
	p.queue_free()


## Server -> owner: send the private inventory state.
func push_inventory() -> void:
	# a freshly spawned node isn't visible to its owner yet; Main pushes again
	# 0.2s after every spawn, so nothing is lost by skipping here
	if multiplayer.is_server() and Time.get_ticks_msec() - _born_ms >= 150 and _owner_connected():
		client_set_inventory.rpc_id(peer_id, inventory, gold, equipment, bag, stash)
		client_set_talents.rpc_id(peer_id, talents)
		push_atlas()
		push_hideout()


func push_hideout() -> void:
	if multiplayer.is_server() and Time.get_ticks_msec() - _born_ms >= 150 and _owner_connected():
		client_set_hideout.rpc_id(peer_id, hideout)


@rpc("authority", "call_local", "reliable")
func client_set_hideout(h: Dictionary) -> void:
	hideout = h
	inventory_changed.emit()


## Server -> owner: atlas progress, daily ticket and the open run (for the merchant / device / atlas panels).
func push_atlas() -> void:
	if multiplayer.is_server() and Time.get_ticks_msec() - _born_ms >= 150 and _owner_connected() and _main and _main.instances:
		client_set_atlas.rpc_id(peer_id, atlas, free_day, _main.instances.run_info_for(account_key))


# ================================================================ talents (server)

func server_learn_talent(id: String) -> void:
	var why := Talents.can_learn(class_id, level, talents, id)
	if why != "":
		_srv_log("%s passive %s rejected: %s" % [display_name, id, why])
		notify("Passive: " + why)
		return
	var before := _stat_line()
	var hp_frac := float(hp) / float(maxi(1, max_hp))
	talents[id] = 1
	recalc_stats()
	hp = clampi(roundi(max_hp * hp_frac), 1, max_hp)
	var n := Talents.node(id)
	_srv_log("%s allocated passive %s [%s] (%d/%d points spent) | %s -> %s" % [display_name, n["name"], n["type"],
		Talents.points_spent(talents), Talents.points_total(level), before, _stat_line()])
	push_inventory()


func server_refund_node(id: String) -> void:
	var why := Talents.can_refund(class_id, talents, id)
	var cost := Talents.refund_cost(level)
	if why == "" and gold < cost:
		why = "not enough gold (%d/%d)" % [gold, cost]
	if why != "":
		_srv_log("%s refund %s rejected: %s" % [display_name, id, why])
		notify("Refund: " + why)
		return
	gold -= cost
	var before := _stat_line()
	talents.erase(id)
	recalc_stats()
	hp = mini(hp, max_hp)
	_srv_log("%s refunded passive %s for %d gold (gold left %d, %d/%d points spent) | %s -> %s" % [display_name,
		Talents.node(id)["name"], cost, gold, Talents.points_spent(talents), Talents.points_total(level), before, _stat_line()])
	notify("Refunded %s (-%d gold)" % [Talents.node(id)["name"], cost], true)
	push_inventory()


func server_respec() -> void:
	var spent := Talents.points_spent(talents)
	var cost := Talents.respec_cost(level)
	if spent == 0:
		_srv_log("%s respec rejected: no passives to reset" % display_name)
		notify("Nothing to reset")
		return
	if gold < cost:
		_srv_log("%s respec rejected: not enough gold (%d/%d)" % [display_name, gold, cost])
		notify("Passive web reset costs %d gold (you have %d)" % [cost, gold])
		return
	gold -= cost
	var before := _stat_line()
	talents = {}
	recalc_stats()
	hp = mini(hp, max_hp)
	_srv_log("%s reset passive web: refunded %d points for %d gold (gold left %d) | %s -> %s" % [display_name, spent, cost, gold, before, _stat_line()])
	notify("Passive web reset (-%d gold)" % cost, true)
	push_inventory()


func _stat_line() -> String:
	return "hp %d mp %d atk %d def %d crit %.1f%% critx%.2f speed %d" % [max_hp, max_mp, attack, defense, crit * 100.0, crit_mult(), roundi(move_speed)]


# ================================================================ requests from the owner
# The owning client sends these through Main.player_request (a stable node path,
# so requests still land correctly while the player is changing zones).

func handle_request(action: String, arg: Variant) -> void:
	match action:
		"input":
			if arg is Vector2:
				server_set_input(arg)
		"attack":
			server_attack(arg if typeof(arg) == TYPE_DICTIONARY else {})
		"pickup":
			server_pickup()
		"use":
			server_use_item(str(arg))
		"equip":
			server_equip(arg)
		"craft":
			server_craft(arg)
		"sell":
			server_sell(arg)
		"drop_item":
			server_drop_item(arg)
		"destroy_item":
			server_destroy_item(arg)
		"stash":
			server_stash(arg)
		"unequip":
			server_unequip(str(arg))
		"skill":
			if typeof(arg) == TYPE_INT:
				SkillCaster.cast(self, int(arg), {})
			elif typeof(arg) == TYPE_DICTIONARY and typeof(arg.get("slot")) == TYPE_INT:
				SkillCaster.cast(self, int(arg["slot"]), arg)
		"talent":
			server_learn_talent(str(arg))
		"respec":
			server_respec()
		"refund":
			server_refund_node(str(arg))
		"dungeon":
			if _main and _main.instances and typeof(arg) == TYPE_DICTIONARY:
				_main.instances.handle_request(self, arg)
		"hideout":
			if _main and _main.hideouts and typeof(arg) == TYPE_DICTIONARY:
				_main.hideouts.handle_request(self, arg)
		"market":
			if _main and _main.market and typeof(arg) == TYPE_DICTIONARY:
				_main.market.handle_request(self, arg)


func server_set_input(dir: Vector2) -> void:
	_input_dir = Vector2.ZERO if dead else dir.limit_length(1.0)


func server_attack(req: Dictionary = {}) -> void:
	if _attack_cd > 0.0 or dead:
		return
	var aspd := 1.0 + tm("attack_speed") / 100.0
	_attack_cd = ATTACK_COOLDOWN / aspd
	if Classes.info(class_id)["basic"] == "ranged":
		# Water / Fire: a short-range bolt at the selected target, else toward the
		# cursor, else at the nearest monster (or straight ahead)
		_attack_cd = (ATTACK_COOLDOWN + 0.15) / aspd
		var dir: Vector2 = SkillCaster.aim_direction(self, req, RANGED_BASIC_RANGE, "basic bolt")
		facing = dir
		zone.spawn_player_projectile(position + Vector2(0, -10), dir * 300.0, "ice" if element == "water" else "fire",
			self, {"mult": 1.0, "basic": true, "range": RANGED_BASIC_RANGE, "name": "Frost Bolt" if element == "water" else "Fire Bolt"})
		return
	var sel: Node = SkillCaster.resolve_target(self, req, ATTACK_RANGE + 30.0, "basic attack", false)
	if sel and sel.has_method("take_damage"):
		facing = position.direction_to(sel.position)
	for m in zone.monsters_root.get_children():
		var reach := ATTACK_RANGE + (12.0 * float(m.def.get("scale", 1.0)) if m.is_boss else 0.0)
		if m.alive and not m.is_queued_for_deletion() and m.position.distance_to(position) <= reach:
			hit_monster(m, 1.0, {"basic_melee": true})
	if _main:
		_main.zone_rpc(self, "play_swing")


func server_pickup() -> void:
	if dead:
		return
	var best: Node = null
	for p in zone.loot_root.get_children():
		var d: float = p.position.distance_to(position)
		if not p.is_queued_for_deletion() and d <= PICKUP_RANGE and (best == null or d < best.position.distance_to(position)):
			best = p
	if best:
		_server_take_pickup(best)


func server_use_item(item_id: String) -> void:
	if dead:
		return
	if int(inventory.get(item_id, 0)) <= 0 or Items.type_of(item_id) != "consumable":
		return
	if hp >= max_hp:
		return
	_take_one(item_id)
	var heal := Items.stat(item_id, "heal")
	hp = mini(max_hp, hp + heal)
	_srv_log("%s used %s (+%d hp -> %d/%d)" % [display_name, item_id, heal, hp, max_hp])
	push_inventory()


# ================================================================ gear (server)

## Bag slots in use: one per distinct stack + one per gear instance.
func bag_used() -> int:
	return inventory.size() + bag.size()


func bag_full() -> bool:
	return bag_used() >= Items.BAG_SIZE


func find_bag(uid: int) -> int:
	for i in bag.size():
		if int(bag[i].get("uid", -1)) == uid:
			return i
	return -1


func find_equipped(uid: int) -> String:
	for slot in equipment:
		if not equipment[slot].is_empty() and int(equipment[slot].get("uid", -1)) == uid:
			return slot
	return ""


func near_map_device() -> bool:
	return zone != null and zone.has_method("map_device_pos") and zone.map_device_pos() != Vector2.INF \
		and position.distance_to(zone.map_device_pos()) <= BLACKSMITH_RANGE


func near_merchant() -> bool:
	return zone != null and zone.has_method("merchant_pos") and zone.merchant_pos() != Vector2.INF \
		and position.distance_to(zone.merchant_pos()) <= BLACKSMITH_RANGE


func near_broker() -> bool:
	return zone != null and zone.has_method("broker_pos") and zone.broker_pos() != Vector2.INF \
		and position.distance_to(zone.broker_pos()) <= BLACKSMITH_RANGE


func near_blacksmith() -> bool:
	return zone != null and zone.has_method("blacksmith_pos") and zone.blacksmith_pos() != Vector2.INF \
		and position.distance_to(zone.blacksmith_pos()) <= BLACKSMITH_RANGE


func _uid_of(arg: Variant) -> int:
	if typeof(arg) == TYPE_DICTIONARY:
		return int(arg.get("uid", -1))
	if typeof(arg) == TYPE_INT or typeof(arg) == TYPE_FLOAT:
		return int(arg)
	return -1


func _gear_reject(what: String, why: String) -> void:
	_srv_log("%s %s rejected: %s" % [display_name, what, why])
	notify("%s: %s" % [what.capitalize(), why])


func server_equip(arg: Variant) -> void:
	var uid := _uid_of(arg)
	var i := find_bag(uid)
	if i < 0:
		return
	var inst: Dictionary = bag[i]
	var base := str(inst["base"])
	if not Items.can_use(base, class_id):
		_srv_log("%s can't equip %s (%s)" % [display_name, base, Items.class_note(base)])
		notify("%s: %s" % [Gear.display_name(inst), Items.class_note(base)], true)
		return
	if level < Gear.req_level(inst):
		_gear_reject("equip", "%s requires level %d" % [Gear.display_name(inst), Gear.req_level(inst)])
		return
	var slots := Items.slots_for(base)
	var slot: String = slots[0]
	if typeof(arg) == TYPE_DICTIONARY and str(arg.get("slot", "")) in slots:
		slot = str(arg["slot"])
	elif slots.size() > 1:
		for sl in slots:
			if equipment[sl].is_empty():
				slot = sl
				break
	var before := _stat_line()
	bag.remove_at(i)
	var old: Dictionary = equipment[slot]
	if not old.is_empty():
		bag.insert(i, old)
	equipment[slot] = inst
	recalc_stats()
	_srv_log("%s equipped %s in %s (attack %d, defense %d) | %s -> %s | res %s" % [display_name, Gear.summary(inst), slot,
		attack, defense, before, _stat_line(), _res_line()])
	push_inventory()


func server_unequip(slot: String) -> void:
	if not equipment.has(slot) or equipment[slot].is_empty():
		return
	if bag_full():
		_gear_reject("unequip", "your bag is full (%d/%d)" % [bag_used(), Items.BAG_SIZE])
		return
	var old: Dictionary = equipment[slot]
	var before := _stat_line()
	equipment[slot] = {}
	bag.append(old)
	recalc_stats()
	_srv_log("%s unequipped %s | %s -> %s" % [display_name, Gear.summary(old), before, _stat_line()])
	push_inventory()


## Crafting: {orb, uid}. Orbs work anywhere; enhancement stones only at the blacksmith (gold cost).
func server_craft(arg: Variant) -> void:
	if typeof(arg) != TYPE_DICTIONARY:
		return
	var orb := str(arg.get("orb", ""))
	var uid := _uid_of(arg)
	if not orb in Items.ORBS:
		_gear_reject("craft", "'%s' is not crafting currency" % orb)
		return
	if int(inventory.get(orb, 0)) <= 0:
		_gear_reject("craft", "you have no %s" % Items.display_name(orb))
		return
	var where := "bag"
	var inst: Dictionary = {}
	var bi := find_bag(uid)
	if bi >= 0:
		inst = bag[bi]
	else:
		var sl := find_equipped(uid)
		if sl != "":
			inst = equipment[sl]
			where = sl
	if inst.is_empty():
		_gear_reject("craft", "item %d not found" % uid)
		return
	var before := Gear.summary(inst)
	if orb == "enhance_stone" and Dungeons.is_ticket(inst):
		_gear_reject("enhance", "Dungeon Tickets can't be enhanced (use a Cartographer's Chisel for quality)")
		return
	if orb == "enhance_stone":
		if not near_blacksmith():
			_gear_reject("enhance", "you must be at the blacksmith in Sunny Meadow")
			return
		var u := int(inst.get("upg", 0))
		if u >= Gear.MAX_UPG:
			_gear_reject("enhance", "%s is already +%d (max)" % [Gear.display_name(inst), Gear.MAX_UPG])
			return
		var cost := Gear.enhance_gold(u)
		if gold < cost:
			_gear_reject("enhance", "not enough gold (%d/%d)" % [gold, cost])
			return
		gold -= cost
		_take_one(orb)
		var res := Gear.enhance(inst, _rng)
		_srv_log("%s enhance %s: +%d -> +%d %s (chance %d%%, cost %d gold, gold left %d)" % [display_name, before,
			int(res["from"]), int(res["to"]), str(res["result"]).to_upper(), roundi(float(res["chance"]) * 100.0), cost, gold])
		notify({"success": "Enhanced to +%d!", "fail": "Enhancement failed (still +%d)", "downgrade": "Failed - dropped to +%d"}[res["result"]] % int(res["to"]), true)
	else:
		var why := Gear.apply_orb(inst, orb, _rng, class_id)
		if why != "":
			_gear_reject("craft", "%s on %s: %s" % [Items.display_name(orb), Gear.display_name(inst), why])
			return
		_take_one(orb)
		var affix_list: Array = []
		for e in inst["mods"]:
			affix_list.append("%s %s" % [e[1], str(e[2])])
		_srv_log("%s used %s on %s -> %s {%s}%s" % [display_name, Items.display_name(orb), before, Gear.summary(inst), ", ".join(affix_list),
			"" if where == "bag" else " (equipped in %s) | %s" % [where, "stats recalculated"]])
	if where != "bag":
		recalc_stats()
	push_inventory()


func server_sell(arg: Variant) -> void:
	if not near_blacksmith():
		_gear_reject("sell", "you must be at the blacksmith in Sunny Meadow")
		return
	if typeof(arg) == TYPE_DICTIONARY and arg.has("stack"):
		var id := str(arg["stack"])
		var n := int(inventory.get(id, 0))
		var each := int(Items.info(id).get("sell", 0))
		if n <= 0 or each <= 0:
			_gear_reject("sell", "the blacksmith won't buy that")
			return
		inventory.erase(id)
		gold += n * each
		_srv_log("%s sold %d x %s for %d gold" % [display_name, n, id, n * each])
		push_inventory()
		return
	var i := find_bag(_uid_of(arg))
	if i < 0:
		_gear_reject("sell", "item not in your bag")
		return
	var inst: Dictionary = bag[i]
	var price := Gear.sell_price(inst)
	bag.remove_at(i)
	gold += price
	_srv_log("%s sold %s for %d gold (gold %d)" % [display_name, Gear.summary(inst), price, gold])
	notify("Sold %s for %d gold" % [Gear.display_name(inst), price], true)
	push_inventory()


func server_drop_item(arg: Variant) -> void:
	if dead or zone == null:
		return
	var i := find_bag(_uid_of(arg))
	if i < 0:
		return
	var inst: Dictionary = bag[i]
	bag.remove_at(i)
	_drop_block_t = 3.0     # don't instantly auto-pick it back up
	zone.spawn_pickup(str(inst["base"]), 1, position + facing * 44.0, inst)
	_srv_log("%s dropped %s on the ground" % [display_name, Gear.summary(inst)])
	push_inventory()


func server_destroy_item(arg: Variant) -> void:
	var i := find_bag(_uid_of(arg))
	if i < 0:
		return
	var inst: Dictionary = bag[i]
	bag.remove_at(i)
	_srv_log("%s destroyed %s" % [display_name, Gear.summary(inst)])
	push_inventory()


func server_stash(arg: Variant) -> void:
	if typeof(arg) != TYPE_DICTIONARY:
		return
	if not near_blacksmith():
		_gear_reject("stash", "the stash is at the blacksmith in Sunny Meadow")
		return
	var uid := _uid_of(arg)
	if str(arg.get("op", "")) == "put":
		var i := find_bag(uid)
		if i < 0:
			return
		if stash.size() >= Items.STASH_SIZE:
			_gear_reject("stash", "the stash is full")
			return
		stash.append(bag[i])
		_srv_log("%s stashed %s (%d/%d in stash)" % [display_name, Gear.summary(bag[i]), stash.size(), Items.STASH_SIZE])
		bag.remove_at(i)
	else:
		for j in stash.size():
			if int(stash[j].get("uid", -1)) == uid:
				if bag_full():
					_gear_reject("stash", "your bag is full")
					return
				bag.append(stash[j])
				_srv_log("%s took %s from the stash" % [display_name, Gear.summary(stash[j])])
				stash.remove_at(j)
				break
	push_inventory()


func _take_one(item_id: String) -> void:
	var n := int(inventory.get(item_id, 0)) - 1
	if n <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = n


@rpc("authority", "call_local", "reliable")
func client_set_atlas(a: Dictionary, fd: String, ri: Dictionary) -> void:
	atlas = a
	free_day = fd
	run_info = ri
	inventory_changed.emit()


@rpc("authority", "call_local", "reliable")
func client_set_talents(t: Dictionary) -> void:
	talents = t
	tmods = Stats.gather(class_id, talents, equipment)
	inventory_changed.emit()


@rpc("authority", "call_local", "reliable")
func client_set_inventory(inv: Dictionary, g: int, eq: Dictionary, b: Array, st: Array) -> void:
	inventory = inv
	gold = g
	equipment = eq
	bag = b
	stash = st
	tmods = Stats.gather(class_id, talents, equipment)
	inventory_changed.emit()


@rpc("authority", "call_local", "reliable")
func client_skill_cast(slot: int, cd: float) -> void:
	cd_client[slot] = [Time.get_ticks_msec() + int(cd * 1000.0), cd]


@rpc("authority", "call_local", "reliable")
func client_notice(text: String, to_chat: bool) -> void:
	NetUtil.popup(self, text, Color(0.8, 0.9, 1.0), -70.0)
	if _main:
		_main.local_notice(text, to_chat)


## Server -> owner: a short message over your head (and optionally in chat).
func notify(text: String, to_chat := false) -> void:
	if multiplayer.is_server() and Time.get_ticks_msec() - _born_ms >= 150 and _owner_connected():
		client_notice.rpc_id(peer_id, text, to_chat)


## The owning peer is still connected (or is the listen-server host itself).
func _owner_connected() -> bool:
	return peer_id == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer_id)


@rpc("authority", "call_local", "reliable")
func play_swing() -> void:
	_swing_t = SWING_TIME


# ================================================================ combat (server)

## Server: per-tick buffs, mana regen, cooldowns and delayed skill effects.
func _combat_tick(delta: float) -> void:
	for i in 4:
		_cooldowns[i] = maxf(0.0, _cooldowns[i] - delta)
	_mp_regen_t += delta
	if _mp_regen_t >= 0.5:
		_mp_regen_t = 0.0
		if mp < max_mp:
			mp = mini(max_mp, mp + maxi(1, roundi(max_mp * (0.02 if _since_hit < 4.0 else 0.04) * (1.0 + tm("mp_regen_pct") / 100.0) * (1.0 - zone.dungeon_mod("map_less_mana_regen") / 100.0))))
	_phoenix_cd = maxf(0.0, _phoenix_cd - delta)
	if _shield_t > 0.0:
		_shield_t -= delta
		if _shield_t <= 0.0:
			_shield = 0
			_shield_ended()
	if _focus_t > 0.0:
		_focus_t -= delta
	if _fortify_t > 0.0:
		_fortify_t -= delta
	if _hot_t > 0.0:
		_hot_t -= delta
		_hot_acc += _hot_per_sec * delta
		if _hot_acc >= 1.0:
			var h := int(_hot_acc)
			_hot_acc -= h
			hp = mini(max_hp, hp + h)
	if not _pending.is_empty():
		var due: Array = []
		for e in _pending:
			e[0] -= delta
			if e[0] <= 0.0:
				due.append(e)
		for e in due:
			_pending.erase(e)
			(e[1] as Callable).call()
	_update_status_flags()


func _update_status_flags() -> void:
	var f := 0
	if _shield > 0:
		f |= ST_SHIELD
	if _focus_t > 0.0:
		f |= ST_FOCUS
	if _hot_t > 0.0:
		f |= ST_REGROWTH
	if _fortify_t > 0.0:
		f |= ST_FORTIFY
	status_flags = f


## Earth capstone: a breaking / expiring Stone Skin erupts and stuns.
func _shield_ended() -> void:
	if _shield_name != "Stone Skin" or tm("flag:unbreakable") <= 0.0 or dead:
		return
	SkillCaster.fx(self, "ring", position, 110.0)
	var n := 0
	for m in SkillCaster.monsters_in(self, position, 110.0):
		m.add_stun(1.5, display_name)
		n += 1
	_srv_log("%s's Unbreakable shield erupts, stunning %d enemies" % [display_name, n])


## Rate-limited log for frequent talent procs.
func _tlog(key: String, msg: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_talent_log_ms.get(key, -99999)) > 3000:
		_talent_log_ms[key] = now
		_srv_log(msg)


func crit_chance() -> float:
	return crit + (0.4 if _focus_t > 0.0 else 0.0)


func attack_mult() -> float:
	return 1.25 if _focus_t > 0.0 else 1.0


## Server: deal `mult` x attack to a monster, with crits, the element cycle and
## the skill's status effects (poison / burn / slow / stun).
func hit_monster(m: Node, mult: float, sk: Dictionary) -> void:
	if not is_instance_valid(m) or not m.alive or m.is_queued_for_deletion():
		return
	var is_crit: bool = sk.get("crit", false) or randf() < crit_chance()
	var emult := Classes.multiplier(element, m.element)
	var bonus := 1.0 + tm("dmg_vs:" + m.element) / 100.0
	if tm("vs_slowed") > 0.0 and (m.status_flags & (m.ST_SLOW | m.ST_STUN)) != 0:
		bonus += tm("vs_slowed") / 100.0
		_tlog("shatter", "%s's Shatter: +%d%% vs slowed/frozen %s" % [display_name, roundi(tm("vs_slowed")), m.display_name])
	if (sk.get("execute", false) or tm("flag:deathmark") > 0.0) and m.hp * 10 < m.max_hp * 3:
		bonus *= 2.0
		_tlog("execute", "%s's Death Mark executes %s (double damage below 30%% HP)" % [display_name, m.display_name])
	if not sk.get("basic_melee", false) and not sk.get("basic", false) and tm("ele_dmg_pct") != 0.0:
		bonus *= 1.0 + tm("ele_dmg_pct") / 100.0     # gear: increased elemental (skill) damage
	var dmg := maxi(1, roundi(attack * mult * attack_mult() * (crit_mult() if is_crit else 1.0) * emult * bonus))
	if sk.get("basic_melee", false) and tm("mp_on_hit") > 0.0:
		mp = mini(max_mp, mp + roundi(tm("mp_on_hit")))
	# leech (fractions accumulate so small hits still count)
	if tm("life_leech") > 0.0 and hp < max_hp:
		_leech_hp += dmg * tm("life_leech") / 100.0
		if _leech_hp >= 1.0:
			var h := int(_leech_hp)
			_leech_hp -= h
			hp = mini(max_hp, hp + h)
			_tlog("leech", "%s leeches %d life (%.1f%% of %d damage)" % [display_name, h, tm("life_leech"), dmg])
	if tm("mana_leech") > 0.0 and mp < max_mp:
		_leech_mp += dmg * tm("mana_leech") / 100.0
		if _leech_mp >= 1.0:
			var n := int(_leech_mp)
			_leech_mp -= n
			mp = mini(max_mp, mp + n)
			_tlog("mleech", "%s leeches %d mana (%.1f%% of %d damage)" % [display_name, n, tm("mana_leech"), dmg])
	m.take_damage(dmg, self, {"crit": is_crit, "emult": emult, "skill": str(sk.get("name", ""))})
	if not m.alive:
		return
	var base := attack * emult
	if sk.has("poison"):
		m.add_dot("poison", maxf(1.0, base * float(sk["poison"][0])), float(sk["poison"][1]), self)
	if sk.has("burn"):
		m.add_dot("burn", maxf(1.0, base * float(sk["burn"][0])), float(sk["burn"][1]), self)
	if sk.has("slow"):
		m.add_slow(float(sk["slow"][0]), float(sk["slow"][1]), display_name)
	if sk.has("stun"):
		m.add_stun(float(sk["stun"]), display_name)


func heal(amount: int, from_name: String) -> void:
	if dead:
		return
	var before := hp
	hp = mini(max_hp, hp + amount)
	if hp > before:
		_srv_log("%s healed %s for %d (hp %d/%d)" % [from_name, display_name, hp - before, hp, max_hp])


# ================================================================ drawing

func _draw() -> void:
	if NetUtil.is_selected(self):
		NetUtil.draw_select_ring(self, 15.0, Color(0.3, 1.0, 0.45))
	# ground-target preview (local player holding a skill key / hovering the skill bar)
	if is_local() and _main and _main.preview_slot >= 0 and not dead:
		_draw_preview(_main.preview_slot)
	# shadow
	draw_set_transform(Vector2(0, 3), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# buff auras
	if not dead and status_flags != 0:
		if status_flags & ST_SHIELD:
			draw_circle(Vector2(0, -10), 20.0, Color(0.8, 0.6, 0.3, 0.25))
			draw_arc(Vector2(0, -10), 20.0, 0.0, TAU, 24, Color(0.85, 0.65, 0.35, 0.9), 2.0)
		if status_flags & ST_FOCUS:
			draw_arc(Vector2(0, 0), 14.0 + sin(_anim_t + Time.get_ticks_msec() * 0.01) * 2.0, 0.0, TAU, 20, Color(1, 0.9, 0.4, 0.8), 2.0)
		if status_flags & ST_REGROWTH:
			var t := Time.get_ticks_msec() * 0.004
			for i in 3:
				var a := t + i * TAU / 3.0
				draw_circle(Vector2(cos(a) * 14.0, -10 + sin(a) * 6.0), 2.5, Color(0.4, 1.0, 0.4, 0.9))
		if status_flags & ST_FORTIFY:
			draw_rect(Rect2(-14, -28, 28, 30), Color(0.75, 0.55, 0.3, 0.8), false, 2.0)
	# hp + mana bars
	if not dead:
		var w := 28.0
		draw_rect(Rect2(-w / 2 - 1, -36, w + 2, 7), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2, -35, w * float(hp) / float(maxi(1, max_hp)), 3), Color(0.3, 0.9, 0.3) if hp * 3 > max_hp else Color(0.95, 0.3, 0.25))
		draw_rect(Rect2(-w / 2, -32, w * float(mp) / float(maxi(1, max_mp)), 2), Color(0.35, 0.6, 1.0))
	# element icon next to the name
	if not _elem_tex.has(element):
		_elem_tex[element] = Classes.element_icon(element)
	draw_texture_rect(_elem_tex[element], Rect2(_icon_x - 7, -51, 14, 14), false)
	# sword swing
	if _swing_t > 0.0:
		var a := facing.angle()
		var alpha := _swing_t / SWING_TIME
		var ec := Classes.color(element)
		draw_arc(Vector2(0, -8), ATTACK_RANGE * 0.75, a - 1.2, a + 1.2, 16, Color(ec.lerp(Color.WHITE, 0.5), alpha), 4.0)
		draw_arc(Vector2(0, -8), ATTACK_RANGE * 0.55, a - 0.9, a + 0.9, 12, Color(1, 1, 0.6, alpha * 0.7), 2.0)


var _born_ms := Time.get_ticks_msec()
var _icon_x := -40.0
static var _elem_tex := {}

## No floating text for the initial values received right after spawning.
func _popups_ok() -> bool:
	return is_inside_tree() and Time.get_ticks_msec() - _born_ms > 1000
