extends CharacterBody2D
## Generic monster (all types and bosses, see monsters.gd).
## Fully simulated on the server; clients only render the replicated state.

const LEASH := 420.0
const BOSS_LEASH := 360.0

var monster_id: int = 0
var type: String = "slime"
var def: Dictionary = {}
var zone: Node = null
var pack_id: int = -1
var temporary := false        # summoned adds: no respawn, freed on death
var home := Vector2.ZERO
var display_name := "Monster"
var is_boss := false
var defense := 0
var element := ""
# status_flags bits (replicated for visuals)
const ST_POISON := 1
const ST_BURN := 2
const ST_SLOW := 4
const ST_STUN := 8
var _dots := {}               # "poison"/"burn" -> {"dps", "t", "acc", "src"}
var _slow := 0.0
var _slow_t := 0.0
var _stun_t := 0.0
var _taunt_t := 0.0
var _icon_x := -40.0

# Replicated (server -> clients)
var sync_pos: Vector2 = Vector2.ZERO
var hp: int = 10: set = _set_hp
var max_hp: int = 10
var level: int = 1: set = _set_level
var alive: bool = true
var casting: bool = false     # boss telegraph (quake)
var flip: bool = false
var status_flags: int = 0

var target: Node2D = null
var _rng := RandomNumberGenerator.new()
var _dir := Vector2.ZERO
var _think := 0.0
var _respawn_t := 0.0
var _attack_cd := 0.0
var _special_cd := 0.0
var _cast_t := 0.0
var _lunge_t := 0.0
var _lunge_cd := 0.0
var _lunge_dir := Vector2.ZERO
var _no_target_t := 0.0
var _evading := false         # leash broken: walk home, ignore players
var _evade_t := 0.0
var _flash := 0.0
var _bob := 0.0
var _damagers := {}           # peer_id -> player node (for XP/credit)
var _adds: Array = []
var _shape: CollisionShape2D
var _sprite: Sprite2D
var _label: Label
var _tint := Color.WHITE
var _born_ms := Time.get_ticks_msec()
# dungeon instances: map modifiers + elites (see dungeons.gd)
var elite := ""               # "" or an elite modifier (hasted / armoured / brutal / regenerating)
var _dmg_mult := 1.0
var _spd_mult := 1.0
var _regen_acc := 0.0


func setup(id: int, t: String, lv: int, pos: Vector2, pack: int, temp: bool, opts: Dictionary = {}) -> void:
	monster_id = id
	type = t
	def = Monsters.info(t)
	name = "M%d" % id
	pack_id = pack
	temporary = temp
	position = pos
	sync_pos = pos
	home = pos
	is_boss = def.get("boss", false)
	display_name = str(def["name"])
	defense = int(def.get("def", 0))
	element = str(def.get("element", ""))
	if Classes.ELEMENTS.has(str(opts.get("el", ""))):
		element = str(opts["el"])   # dungeon monsters take the dungeon's element
	elite = str(opts.get("elite", ""))
	level = lv
	max_hp = Monsters.max_hp(t, lv)
	_apply_dungeon_mods()
	hp = max_hp
	_rng.seed = id * 7919 + Time.get_ticks_usec()
	_bob = float(id)
	_special_cd = float(def.get("special_cd", 0.0)) * 0.5
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 0 if def.get("flying", false) else 1
	var sc := float(def.get("scale", 1.0)) * (1.25 if elite != "" else 1.0)
	_shape = CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 9.0 * minf(sc, 1.6)
	_shape.shape = c
	add_child(_shape)
	var tint_arr: Array = def.get("tint", [1, 1, 1])
	_tint = Color(tint_arr[0], tint_arr[1], tint_arr[2], float(def.get("alpha", 1.0)))
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/monsters/%s.png" % def["sprite"])
	_sprite.offset = Vector2(0, -12)
	_sprite.scale = Vector2(sc, sc)
	_sprite.modulate = _tint
	add_child(_sprite)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(180, 16)
	_label.position = Vector2(-90, -34 * sc - 28)
	_label.z_index = 10
	_label.add_theme_font_size_override("font_size", 13 if is_boss else 10)
	var ec := Classes.color(element)
	_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3) if is_boss else (Color(1.0, 0.92, 0.35) if elite != "" else ec.lerp(Color.WHITE, 0.45)))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_update_label()
	add_child(NetUtil.make_synchronizer(["sync_pos"], ["hp", "max_hp", "level", "alive", "casting", "flip", "status_flags"]))


## Map modifiers of the dungeon this monster lives in (+ its elite modifier). Server and clients
## run this alike (max_hp is replicated anyway; the rest only matters on the server).
func _apply_dungeon_mods() -> void:
	var dm: Dictionary = zone.info.get("dungeon", {}).get("mods", {}) if zone else {}
	max_hp = roundi(max_hp * (1.0 + float(dm.get("map_mon_hp", 0.0)) / 100.0))
	_dmg_mult = 1.0 + (float(dm.get("map_mon_dmg", 0.0)) + float(dm.get("map_extra_ele", 0.0))) / 100.0
	_spd_mult = 1.0 + float(dm.get("map_mon_speed", 0.0)) / 100.0
	defense += int(dm.get("map_mon_def", 0.0))
	if elite != "":
		max_hp = roundi(max_hp * 2.5)
		_dmg_mult *= 1.3
		display_name = "%s %s" % [Dungeons.ELITE_NAMES.get(elite, "Elite"), display_name]
		match elite:
			"hasted": _spd_mult *= 1.35
			"armoured": defense += 5
			"brutal": _dmg_mult *= 1.3


## Outgoing damage after map modifiers / elite bonus.
func _dmg(base: int = -1) -> int:
	return maxi(1, roundi((Monsters.damage(type, level) if base < 0 else base) * _dmg_mult))


func _set_hp(v: int) -> void:
	var diff := v - hp
	if diff < 0:
		_flash = 0.15
		if _popups_ok():
			NetUtil.popup(self, str(diff), Color(1, 1, 0.5), -40.0 * float(def.get("scale", 1.0)))
	hp = v


func _set_level(v: int) -> void:
	level = v
	_update_label()


func _update_label() -> void:
	if _label:
		_label.text = ("★ %s  Lv %d" if is_boss else ("◆ %s  Lv %d" if elite != "" else "%s  Lv %d")) % [display_name, level]
		var fs := 13 if is_boss else 10
		var w := _label.get_theme_font("font").get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_icon_x = -w / 2.0 - 8.0


func _popups_ok() -> bool:
	return is_inside_tree() and Time.get_ticks_msec() - _born_ms > 1000


func _srv_log(msg: String) -> void:
	print("[%s] [SERVER] [%s] %s" % [Time.get_time_string_from_system(), zone.zone_id if zone else "?", msg])


# ================================================================ server: combat

## Server only. `attacker` is the player node that hit us.
## `opts`: crit (bool), emult (element multiplier, for the log), skill (name), dot (true = ignores defense)
func take_damage(amount: int, attacker: Node, opts: Dictionary = {}) -> void:
	if not alive:
		return
	var dmg := maxi(1, amount if opts.get("dot", false) else amount - defense)
	hp = maxi(0, hp - dmg)
	_damagers[attacker.peer_id] = attacker
	if target == null and not _evading:
		_set_target(attacker)
	if not opts.get("dot", false) and (not is_boss or hp == 0 or hp % 50 < dmg or opts.get("emult", 1.0) != 1.0):
		var note := ""
		if opts.get("skill", "") != "":
			note += " with " + str(opts["skill"])
		if opts.get("crit", false):
			note += " CRIT"
		var em := float(opts.get("emult", 1.0))
		if em != 1.0:
			note += " [%s%s%s x%.2f]" % [Classes.ELEMENT_INFO[attacker.element]["name"], ">" if em > 1.0 else "<",
				Classes.ELEMENT_INFO[element]["name"], em]
		_srv_log("%s hit %s(Lv%d) for %d%s -> hp %d/%d" % [attacker.display_name, display_name, level, dmg, note, hp, max_hp])
	if hp == 0:
		_die(attacker)


# ================================================================ server: status effects

func add_dot(kind: String, dps: float, duration: float, src: Node) -> void:
	if not alive:
		return
	var fresh := not _dots.has(kind)
	_dots[kind] = {"dps": dps, "t": duration, "acc": 0.0, "src": src}
	if fresh:
		_srv_log("%s is %s (%.1f/s for %.0fs) by %s" % [display_name, "poisoned" if kind == "poison" else "burning",
			dps, duration, src.display_name])


func add_slow(amount: float, duration: float, by: String) -> void:
	if is_boss:
		amount *= 0.5
	if _slow_t <= 0.0:
		_srv_log("%s is slowed by %d%% (%.1fs) by %s" % [display_name, roundi(amount * 100.0), duration, by])
	_slow = maxf(_slow, amount)
	_slow_t = maxf(_slow_t, duration)


func add_stun(duration: float, by: String) -> void:
	if is_boss:
		duration *= 0.5   # bosses shrug stuns off faster
	if _stun_t <= 0.0:
		_srv_log("%s is stunned for %.1fs by %s" % [display_name, duration, by])
	_stun_t = maxf(_stun_t, duration)


func taunt(p: Node2D, duration: float) -> void:
	if not alive:
		return
	_evading = false
	target = p
	_taunt_t = duration
	_srv_log("%s is taunted by %s" % [display_name, p.display_name])


func _status_tick(delta: float) -> void:
	for kind in _dots.keys():
		var d: Dictionary = _dots[kind]
		d["t"] -= delta
		d["acc"] += float(d["dps"]) * delta
		if d["acc"] >= 1.0 and is_instance_valid(d["src"]):
			var n := int(d["acc"])
			d["acc"] -= n
			take_damage(n, d["src"], {"dot": true})
			if not alive:
				return
		if d["t"] <= 0.0 or not is_instance_valid(d["src"]):
			_dots.erase(kind)
	if _slow_t > 0.0:
		_slow_t -= delta
		if _slow_t <= 0.0:
			_slow = 0.0
	if _stun_t > 0.0:
		_stun_t -= delta
	if _taunt_t > 0.0:
		_taunt_t -= delta
	var f := 0
	if _dots.has("poison"):
		f |= ST_POISON
	if _dots.has("burn"):
		f |= ST_BURN
	if _slow_t > 0.0:
		f |= ST_SLOW
	if _stun_t > 0.0:
		f |= ST_STUN
	status_flags = f


func _die(killer: Node) -> void:
	alive = false
	casting = false
	target = null
	# Wood capstone: poison jumps from a dying enemy
	if _dots.has("poison"):
		var src = _dots["poison"]["src"]
		if is_instance_valid(src) and src.tm("flag:pandemic") > 0.0:
			var n := 0
			for m in zone.monsters_root.get_children():
				if m != self and m.alive and m.position.distance_to(position) <= 100.0:
					m.add_dot("poison", float(_dots["poison"]["dps"]), 5.0, src)
					n += 1
			if n > 0:
				_srv_log("Pandemic: %s's poison jumps from %s to %d enemies" % [src.display_name, display_name, n])
	_dots.clear()
	_slow_t = 0.0
	_slow = 0.0
	_stun_t = 0.0
	_taunt_t = 0.0
	status_flags = 0
	_shape.set_deferred("disabled", true)
	var xp := Monsters.xp_reward(type, level)
	var names: Array = []
	for pid in _damagers:
		var p = _damagers[pid]
		if is_instance_valid(p) and p.zone == zone and not p.is_queued_for_deletion():
			p.server_add_xp(xp)
			names.append(p.display_name)
	_damagers.clear()
	_srv_log("%s(Lv%d) was slain by %s (+%d XP each)" % [display_name, level, ", ".join(names), xp])
	zone.drop_loot(position, type, level, killer, self)
	zone.on_monster_died(self, killer)
	if is_boss:
		zone.main.broadcast_system("%s defeated %s in %s!" % [" & ".join(names), display_name, zone.info["name"]])
	for a in _adds:
		if is_instance_valid(a):
			a.queue_free()
	_adds.clear()
	if temporary:
		queue_free()
		return
	_respawn_t = float(def["respawn"]) * zone.main.respawn_scale


func _respawn() -> void:
	if is_boss:
		position = home
	else:
		position = zone.map.random_open_position(_rng, zone.avoid_cells())
		home = position
	sync_pos = position
	hp = max_hp
	alive = true
	_shape.set_deferred("disabled", false)
	_srv_log("%s(Lv%d) respawned at %s" % [display_name, level, position.round()])
	if is_boss:
		zone.main.broadcast_system("%s has returned to %s!" % [display_name, zone.info["name"]])


func _set_target(p: Node2D) -> void:
	if p == target:
		return
	var had := target != null
	target = p
	if p and not had:
		if is_boss:
			_srv_log("%s is now fighting %s" % [display_name, p.display_name])
		if def["behavior"] == "pack":
			for m in zone.monsters_root.get_children():
				if m != self and m.pack_id == pack_id and m.alive and m.target == null:
					m.target = p


func _target_valid(p) -> bool:
	return is_instance_valid(p) and not p.is_queued_for_deletion() and p.zone == zone and not p.dead


# ================================================================ server: AI

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)
	else:
		if not visible and alive:
			position = sync_pos
		NetUtil.smooth_follow(self, sync_pos, delta)
	visible = alive
	_bob += delta * 6.0
	if _flash > 0.0:
		_flash -= delta
	if _sprite:
		var squish := 1.0 + 0.06 * sin(_bob)
		var sc := float(def.get("scale", 1.0))
		_sprite.scale = Vector2(sc * squish, sc / squish)
		_sprite.flip_h = flip
		if def.get("flying", false):
			_sprite.position.y = -4.0 + sin(_bob * 1.3) * 3.0
		var m := _tint
		if status_flags & ST_POISON:
			m = m * Color(0.6, 1.0, 0.6)
		if status_flags & ST_BURN:
			m = m * Color(1.0, 0.65, 0.45)
		if status_flags & ST_SLOW:
			m = m * Color(0.65, 0.8, 1.2)
		_sprite.modulate = Color(1, 0.4, 0.4, _tint.a) if _flash > 0.0 else m
	queue_redraw()


func _server_tick(delta: float) -> void:
	if not alive:
		_respawn_t -= delta
		if _respawn_t <= 0.0 and not temporary:
			_respawn()
		sync_pos = position
		return
	_status_tick(delta)
	if not alive:
		return
	if elite == "regenerating" and hp < max_hp:
		_regen_acc += max_hp * 0.015 * delta
		if _regen_acc >= 1.0:
			hp = mini(max_hp, hp + int(_regen_acc))
			_regen_acc -= int(_regen_acc)
	if _stun_t > 0.0 and not casting:
		velocity = Vector2.ZERO
		sync_pos = position
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_lunge_cd = maxf(0.0, _lunge_cd - delta)
	_special_cd = maxf(0.0, _special_cd - delta)

	# --- targeting / leash
	if not _target_valid(target):
		target = null   # (also clears references to freed players)
	var leash := BOSS_LEASH if is_boss else LEASH
	if _evading:
		_evade_t += delta
		if _evade_t > 8.0:
			position = home   # got stuck on the way home
		if position.distance_to(home) < 40.0:
			_evading = false
	if target == null and not _evading:
		var p: Node2D = zone.nearest_player(position, float(def["aggro"]))
		if p:
			_set_target(p)
	if target and (position.distance_to(home) > leash or target.position.distance_to(home) > leash + 150.0):
		target = null
		_evading = true
		_evade_t = 0.0
		casting = false
		if is_boss:
			hp = max_hp   # bosses reset when you run away
			_srv_log("%s resets (target out of range)" % display_name)
	if target == null:
		_no_target_t += delta
	else:
		_no_target_t = 0.0

	# --- boss specials
	if is_boss and target:
		_boss_special(delta)
	if casting:
		velocity = Vector2.ZERO
		sync_pos = position
		return

	var speed := float(def["speed"])
	var behavior: String = def["behavior"]
	var to_target := Vector2.ZERO
	var dist := INF
	if target:
		to_target = position.direction_to(target.position)
		dist = position.distance_to(target.position)
		speed = float(def["chase"])
		flip = to_target.x < 0.0

	if _evading:
		_dir = position.direction_to(home)
		speed = float(def["chase"])
	elif target == null:
		if _no_target_t > 4.0 and position.distance_to(home) > 120.0:
			_dir = position.direction_to(home)   # wander back home
		else:
			_think -= delta
			if _think <= 0.0:
				_think = _rng.randf_range(1.0, 3.0)
				_dir = Vector2.ZERO if _rng.randf() < 0.35 else Vector2.from_angle(_rng.randf() * TAU)
		if _dir.x != 0.0:
			flip = _dir.x < 0.0
	else:
		match behavior:
			"ranged":
				var keep := float(def.get("keep", 150.0))
				var room := position.distance_to(home) < leash * 0.7
				if dist < keep - 30.0 and room:
					_dir = -to_target
				elif dist > keep + 30.0:
					_dir = to_target
				else:
					_dir = to_target.orthogonal() * (1.0 if monster_id % 2 == 0 else -1.0) * 0.5
				if dist <= float(def["range"]) and _attack_cd <= 0.0:
					_attack_cd = float(def["cd"])
					zone.spawn_projectile(position + Vector2(0, -10), to_target * 260.0,
						_dmg(), str(def.get("projectile", "arrow")), display_name, element)
			"erratic":
				_think -= delta
				if _think <= 0.0:
					_think = 0.25
					_dir = (to_target + Vector2.from_angle(_rng.randf() * TAU) * 0.9).normalized()
				_try_melee(dist)
			"lunge":
				_dir = to_target
				if _lunge_t > 0.0:
					_lunge_t -= delta
					_dir = _lunge_dir
					speed *= 3.2
				elif dist < 110.0 and dist > 30.0 and _lunge_cd <= 0.0:
					_lunge_cd = 3.0
					_lunge_t = 0.3
					_lunge_dir = to_target
				_try_melee(dist)
			_:
				_dir = to_target if dist > float(def["range"]) * 0.8 else Vector2.ZERO
				_try_melee(dist)

	velocity = _dir * speed * _spd_mult * (1.0 - _slow)
	if def.get("flying", false):
		position += velocity * delta
		var m := 2.5 * Zones.TILE
		position = position.clamp(Vector2(m, m), Vector2(Zones.W * Zones.TILE - m, Zones.H * Zones.TILE - m))
	else:
		move_and_slide()
		if get_slide_collision_count() > 0 and target == null:
			_think = 0.0
	sync_pos = position


func _try_melee(dist: float) -> void:
	if target and dist <= float(def["range"]) and _attack_cd <= 0.0:
		_attack_cd = float(def["cd"])
		target.server_take_damage(_dmg(), display_name, element, self)


func _boss_special(delta: float) -> void:
	var special: String = def.get("special", "")
	if casting:
		_cast_t -= delta
		if _cast_t <= 0.0:
			casting = false
			var dmg := _dmg(20 + level * 2)
			var hits := 0
			for p in zone.players_root.get_children():
				if not p.dead and p.position.distance_to(position) <= 130.0:
					p.server_take_damage(dmg, display_name + "'s Quake", element)
					hits += 1
			_srv_log("%s QUAKE hits %d player(s)" % [display_name, hits])
		return
	if _special_cd > 0.0:
		return
	_special_cd = float(def["special_cd"])
	match special:
		"summon":
			_adds = _adds.filter(func(a): return is_instance_valid(a) and not a.is_queued_for_deletion())
			if _adds.size() < 4:
				for i in 2:
					var a: Node = zone.spawn_monster("spiderling", maxi(1, level - 3),
						position + Vector2.from_angle(_rng.randf() * TAU) * 30.0, -1, true)
					if a:
						a.target = target
						_adds.append(a)
				_srv_log("%s summons spiderlings!" % display_name)
		"volley":
			for i in 12:
				zone.spawn_projectile(position + Vector2(0, -16), Vector2.from_angle(TAU * i / 12.0) * 200.0,
					maxi(1, int(_dmg() * 0.7)), "bolt", display_name, element)
			_srv_log("%s casts Bone Volley!" % display_name)
		"quake":
			casting = true
			_cast_t = 1.2
			_srv_log("%s raises its fists... (Quake)" % display_name)


# ================================================================ drawing

func _draw() -> void:
	var sc := float(def.get("scale", 1.0))
	if NetUtil.is_selected(self):
		NetUtil.draw_select_ring(self, 15.0 * sc, Color(1.0, 0.3, 0.25))
	if casting:
		draw_circle(Vector2.ZERO, 130.0, Color(1, 0.2, 0.1, 0.18))
		draw_arc(Vector2.ZERO, 130.0, 0.0, TAU, 48, Color(1, 0.3, 0.2, 0.8), 3.0)
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 10.0 * sc, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if status_flags & ST_STUN:
		var t := Time.get_ticks_msec() * 0.006
		for i in 3:
			var a := t + i * TAU / 3.0
			draw_circle(Vector2(cos(a) * 10.0, -30.0 * sc + sin(a) * 3.0), 2.5, Color(1, 0.95, 0.4))
	if status_flags & ST_POISON:
		draw_circle(Vector2(8, -20.0 * sc - 6.0 + sin(_bob) * 2.0), 2.5, Color(0.4, 1.0, 0.3, 0.9))
	if status_flags & ST_BURN:
		draw_circle(Vector2(-8, -20.0 * sc - 8.0 + sin(_bob * 1.7) * 3.0), 3.0, Color(1.0, 0.5, 0.1, 0.9))
	if element != "":
		draw_texture_rect(Classes.element_icon(element), Rect2(_icon_x - 6, -34.0 * sc - 28.0 + 2.0, 12, 12), false)
	if hp < max_hp or is_boss:
		var w := 64.0 if is_boss else 24.0
		var y := -34.0 * sc - 8.0
		draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 6 if is_boss else 5), Color(0.1, 0.1, 0.1, 0.8))
		draw_rect(Rect2(-w / 2, y, w * float(hp) / float(maxi(1, max_hp)), 4 if is_boss else 3), Color(0.9, 0.2, 0.2))
