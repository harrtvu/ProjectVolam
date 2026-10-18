class_name SkillCaster
## Server-side skill logic for all five classes (data in classes.gd).
## Every check (level unlock, cooldown, mana, targets, hits) happens here on the
## server; clients only send "use skill N" and get cooldowns + visual effects back.


static func nearest_monster(p: Node, from: Vector2, max_d: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_d
	for m in p.zone.monsters_root.get_children():
		if not m.alive or m.is_queued_for_deletion():
			continue
		var d: float = m.position.distance_to(from)
		if d < best_d:
			best_d = d
			best = m
	return best


static func monsters_in(p: Node, center: Vector2, radius: float) -> Array:
	var out: Array = []
	for m in p.zone.monsters_root.get_children():
		if m.alive and not m.is_queued_for_deletion():
			var r := radius + (10.0 * float(m.def.get("scale", 1.0)) if m.is_boss else 0.0)
			if m.position.distance_to(center) <= r:
				out.append(m)
	return out


static func _deny(p: Node, slot: int, reason: String, tell := true) -> void:
	var key := "%d:%s" % [slot, reason]
	var now := Time.get_ticks_msec()
	if now - int(p._deny_ms.get(key, -99999)) > 2000:
		p._deny_ms[key] = now
		p._srv_log("%s skill %d rejected: %s" % [p.display_name, slot + 1, reason])
		if tell:
			p.notify(reason)


static func fx(p: Node, kind: String, pos: Vector2, radius: float, extra := Vector2.ZERO) -> void:
	_fx(p, kind, pos, radius, extra)


# ================================================================ targeting
# A request may carry {"t": id, "k": "m"|"p", "aim": Vector2}: the client's selected
# target (monster id / player peer id) and the cursor position in zone coordinates.
# Everything is validated here; invalid targets fall back to the old behaviour
# (nearest monster), so bots and old clients keep working.

static func _tdeny(p: Node, reason: String) -> void:
	var now := Time.get_ticks_msec()
	var why := "other"
	for w in ["another zone", "does not exist", "out of range", "line of sight"]:
		if w in reason:
			why = w
	var key := "t:" + reason.get_slice(":", 0) + ":" + why
	if now - int(p._deny_ms.get(key, -99999)) > 2000:
		p._deny_ms[key] = now
		p._srv_log("%s target rejected: %s" % [p.display_name, reason])


static func _find_in(z: Node, kind: String, id: int) -> Node:
	if kind == "p":
		return z.players_root.get_node_or_null(str(id))
	return z.monsters_root.get_node_or_null("M%d" % id)


## The selected target if it's valid for this use, else null (and logs why).
static func resolve_target(p: Node, req: Dictionary, max_range: float, what: String, need_los := true, want := "enemy") -> Node:
	if typeof(req.get("t")) != TYPE_INT or int(req["t"]) < 0:
		return null
	var kind := str(req.get("k", "m"))
	if kind != "m" and kind != "p":
		return null
	if (want == "enemy") != (kind == "m"):
		return null   # e.g. an ally selected for an attack: just ignore it
	var id := int(req["t"])
	var t := _find_in(p.zone, kind, id)
	if t == null:
		var elsewhere := ""
		if p._main:
			for zid in p._main.zones:
				if p._main.zones[zid] != p.zone and _find_in(p._main.zones[zid], kind, id):
					elsewhere = zid
		_tdeny(p, "%s: target %s%d %s" % [what, kind, id, "is in another zone (%s)" % elsewhere if elsewhere != "" else "does not exist"])
		return null
	if t.is_queued_for_deletion() or ("alive" in t and not t.alive) or ("dead" in t and t.dead):
		_tdeny(p, "%s: %s is dead" % [what, t.display_name])
		return null
	var slack := 24.0 + (12.0 * float(t.def.get("scale", 1.0)) if kind == "m" and t.is_boss else 0.0)
	var d: float = p.position.distance_to(t.position)
	if d > max_range + slack:
		_tdeny(p, "%s: %s is out of range (%d > %d px)" % [what, t.display_name, roundi(d), roundi(max_range)])
		return null
	if need_los and not p.zone.map.has_los(p.position + Vector2(0, -6), t.position + Vector2(0, -6)):
		_tdeny(p, "%s: no line of sight to %s" % [what, t.display_name])
		return null
	var near := nearest_monster(p, p.position, max_range)
	if kind == "m" and near and near != t and p.position.distance_to(near.position) < d - 1.0:
		var key := "sel:%s" % what
		var now := Time.get_ticks_msec()
		if now - int(p._deny_ms.get(key, -99999)) > 2000:
			p._deny_ms[key] = now
			p._srv_log("%s %s uses selected target %s (%d px) over nearer %s (%d px)" % [p.display_name, what,
				t.display_name, roundi(d), near.display_name, roundi(p.position.distance_to(near.position))])
	return t


static func _aim_vec(req: Dictionary) -> Variant:
	var a = req.get("aim")
	if typeof(a) == TYPE_VECTOR2 and a.is_finite():
		return a
	return null


static func _alog(p: Node, key: String, msg: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(p._deny_ms.get("aim:" + key, -99999)) > 2000:
		p._deny_ms["aim:" + key] = now
		p._srv_log(msg)


## The selected enemy of a request even when it is out of range / behind a wall (alive, this zone).
static func _selected_enemy(p: Node, req: Dictionary) -> Node:
	if typeof(req.get("t")) != TYPE_INT or int(req["t"]) < 0 or str(req.get("k", "m")) != "m":
		return null
	var t := _find_in(p.zone, "m", int(req["t"]))
	if t == null or t.is_queued_for_deletion() or not t.alive:
		return null
	return t


## Direction for projectiles / dashes: selected target (even out of range: fly toward it) >
## the CURRENT cursor (sent with the key press) > nearest monster > facing.
static func aim_direction(p: Node, req: Dictionary, max_range: float, what: String) -> Vector2:
	var t := resolve_target(p, req, max_range, what)
	if t == null:
		t = _selected_enemy(p, req)
	if t:
		_alog(p, what + ":t", "%s aims %s at the selected target %s (angle %d)" % [p.display_name, what, t.display_name, roundi(rad_to_deg(p.position.angle_to_point(t.position)))])
		return p.position.direction_to(t.position)
	var aim = _aim_vec(req)
	if aim != null and p.position.distance_to(aim) > 4.0 and int(req.get("t", -1)) < 0:
		_alog(p, what, "%s aims %s at the cursor %s (angle %d)" % [p.display_name, what, Vector2(aim).round(), roundi(rad_to_deg(p.position.angle_to_point(aim)))])
		return p.position.direction_to(aim)
	var n := nearest_monster(p, p.position, max_range)
	if n:
		return p.position.direction_to(n.position)
	return p.facing.normalized() if p.facing != Vector2.ZERO else Vector2.RIGHT


## Point for ground-targeted AoE: selected target > cursor (clamped to range) > nearest monster.
static func aim_point(p: Node, req: Dictionary, max_range: float, what: String) -> Variant:
	var t := resolve_target(p, req, max_range, what, false)
	if t:
		_alog(p, what + ":t", "%s casts %s on the selected target %s" % [p.display_name, what, t.display_name])
		return t.position
	var st := _selected_enemy(p, req)
	if st:   # out of range: as far as it goes toward the target
		return p.position + (st.position - p.position).limit_length(max_range)
	var aim = _aim_vec(req)
	if aim != null and int(req.get("t", -1)) < 0:
		var at: Vector2 = p.position + (Vector2(aim) - p.position).limit_length(max_range)
		_alog(p, what, "%s casts %s at the cursor %s%s" % [p.display_name, what, at.round(),
			"" if at.distance_to(aim) < 1.0 else " (clamped to range from %s)" % Vector2(aim).round()])
		return at
	var n := nearest_monster(p, p.position, max_range)
	return n.position if n else null


static func _fx(p: Node, kind: String, pos: Vector2, radius: float, extra := Vector2.ZERO) -> void:
	if p._main:
		p._main.zone_fx(p.zone, kind, pos, radius, Classes.color(p.element), extra)


## Entry point: owner asked to use skill `slot` (0-3).
static func cast(p: Node, slot: int, req: Dictionary) -> void:
	if p.dead or slot < 0 or slot > 3:
		return
	var sid := Classes.skill_id(p.class_id, slot)
	if sid == "":
		return
	var sk: Dictionary = p.skill_def(sid)
	var need := Classes.skill_unlock_level(slot)
	if p.level < need:
		_deny(p, slot, "%s unlocks at level %d" % [sk["name"], need])
		return
	if p._cooldowns[slot] > 0.0:
		# the client shows its own message from the same counter as the skill bar (one source)
		_deny(p, slot, "%s is on cooldown (%.1fs)" % [sk["name"], p._cooldowns[slot]], false)
		return
	var cost := int(sk["cost"])
	if p.mp < cost:
		_deny(p, slot, "not enough mana for %s (%d/%d)" % [sk["name"], p.mp, cost])
		return
	if not _do(p, sid, sk, req):
		_deny(p, slot, "%s: no target in range" % sk["name"])
		return
	p.mp -= cost
	p._cooldowns[slot] = float(sk["cd"])
	if Time.get_ticks_msec() - p._born_ms >= 150:
		if p._owner_connected():
			p.client_skill_cast.rpc_id(p.peer_id, slot, float(sk["cd"]))
	p._srv_log("%s cast %s (mp %d/%d, cd %.0fs) [cost %d, cd %.1fs%s]" % [p.display_name, sk["name"], p.mp, p.max_mp,
		float(sk["cd"]), cost, float(sk["cd"]), (", x%.2f" % float(sk["mult"])) if sk.has("mult") else ""])


static func _do(p: Node, sid: String, sk: Dictionary, req: Dictionary) -> bool:
	var pos: Vector2 = p.position
	match str(sk["kind"]):
		"aoe_self":
			_fx(p, "ring", pos, float(sk["radius"]))
			for m in monsters_in(p, pos, float(sk["radius"])):
				p.hit_monster(m, float(sk["mult"]), sk)
			if sid == "whirl" and p.tm("flag:bladestorm") > 0.0:
				p._pending.append([0.3, func():
					_fx(p, "ring", p.position, float(sk["radius"]))
					var n := 0
					for m in monsters_in(p, p.position, float(sk["radius"])):
						p.hit_monster(m, float(sk["mult"]) * 0.6, sk)
						n += 1
					p._srv_log("%s's Blade Storm spins again (%d hit)" % [p.display_name, n])])
		"aoe_target":
			var at = aim_point(p, req, float(sk["range"]), str(sk["name"]))
			if at == null:
				return false
			_fx(p, "roots", at, float(sk["radius"]))
			for m in monsters_in(p, at, float(sk["radius"])):
				p.hit_monster(m, float(sk["mult"]), sk)
		"dash":
			var dir: Vector2 = aim_direction(p, req, float(sk["range"]) + 40.0, str(sk["name"]))
			p.facing = dir
			p.move_and_collide(dir * float(sk["range"]))
			var end: Vector2 = p.position
			p.sync_pos = end
			_fx(p, "line", pos, float(sk["width"]), end)
			for m in p.zone.monsters_root.get_children():
				if m.alive and Geometry2D.get_closest_point_to_segment(m.position, pos, end).distance_to(m.position) <= float(sk["width"]) + 10.0:
					p.hit_monster(m, float(sk["mult"]), sk)
		"multi_hit":
			var t := resolve_target(p, req, float(sk["range"]), str(sk["name"]), false)
			if t == null:
				t = nearest_monster(p, pos, float(sk["range"]))
			if t == null:
				return false
			var tid := t.get_instance_id()
			for i in int(sk["hits"]):
				p._pending.append([0.12 * i, func():
					var m = instance_from_id(tid)
					if m and m.alive and m.position.distance_to(p.position) <= float(sk["range"]) + 30.0:
						_fx(p, "slash", m.position, 22.0)
						p.hit_monster(m, float(sk["mult"]), sk)])
		"buff":
			p._focus_t = float(sk["duration"])
			_fx(p, "ring", pos, 40.0)
			p._srv_log("%s gains Blade Focus (+40%% crit, +25%% attack, %.0fs)" % [p.display_name, float(sk["duration"])])
		"projectile":
			var dir: Vector2 = aim_direction(p, req, float(sk["range"]), str(sk["name"]))
			p.facing = dir
			var speed := 360.0 if sk.get("proj", "") != "wave" else 300.0
			p.zone.spawn_player_projectile(pos + Vector2(0, -10), dir * speed, str(sk["proj"]), p, sk)
		"ring":
			var short_sk := sk.duplicate()
			short_sk["range"] = 220.0
			for i in int(sk["count"]):
				p.zone.spawn_player_projectile(pos + Vector2(0, -10), Vector2.from_angle(TAU * i / float(sk["count"])) * 300.0,
					str(sk["proj"]), p, short_sk)
			_fx(p, "ring", pos, 50.0)
		"hot":
			p.heal(roundi(p.max_hp * float(sk["instant"])), p.display_name)
			p._hot_t = float(sk["duration"])
			p._hot_per_sec = p.max_hp * float(sk["per_sec"])
			_fx(p, "heal", pos, 30.0)
			if p.tm("flag:grove_heart") > 0.0:
				var n := 0
				for q in p.zone.players_root.get_children():
					if q != p and not q.dead and q.position.distance_to(pos) <= 150.0:
						q.heal(roundi(q.max_hp * float(sk["instant"]) * 2.0), p.display_name + " (Heart of the Forest)")
						_fx(p, "heal", q.position, 24.0)
						n += 1
				p._srv_log("%s's Heart of the Forest: Regrowth also heals %d allies, -20%% damage taken for %.0fs" % [p.display_name, n, p._hot_t])
		"heal_area":
			# centred on a selected ally (within 300 px), else on yourself
			var ally := resolve_target(p, req, 300.0, str(sk["name"]), false, "ally")
			var center: Vector2 = ally.position if ally else pos
			if ally and ally != p:
				p._srv_log("%s casts Healing Rain on selected ally %s" % [p.display_name, ally.display_name])
			_fx(p, "rain", center, float(sk["radius"]))
			for q in p.zone.players_root.get_children():
				if not q.dead and q.position.distance_to(center) <= float(sk["radius"]):
					var amount: float = q.max_hp * float(sk["heal"])
					if Classes.GENERATES.get(p.element, "") == q.element:
						amount *= 1.2   # Water generates Wood
					q.heal(roundi(amount), p.display_name)
					_fx(p, "heal", q.position, 24.0)
					if p.tm("flag:wellspring") > 0.0:
						q._shield = maxi(q._shield, roundi(q.max_hp * 0.15))
						q._shield_t = 6.0
						q._shield_name = "Wellspring"
						q.mp = mini(q.max_mp, q.mp + roundi(q.max_mp * 0.1))
						q._update_status_flags()
						p._tlog("well", "%s's Wellspring shields %s (%d) and restores mana" % [p.display_name, q.display_name, q._shield])
		"delayed_target":
			var tp = aim_point(p, req, float(sk["range"]), str(sk["name"]))
			if tp == null:
				return false
			var at: Vector2 = tp
			var delay := float(sk["delay"])
			_fx(p, "telegraph", at, float(sk["radius"]), Vector2(delay, 0))
			p._pending.append([delay, func():
				_fx(p, "burst", at, float(sk["radius"]))
				for m in monsters_in(p, at, float(sk["radius"])):
					p.hit_monster(m, float(sk["mult"]), sk)
				if sid == "meteor" and p.tm("flag:meteor_shower") > 0.0:
					var extra: Array = []
					for m in monsters_in(p, at, 260.0):
						if m.position.distance_to(at) > 30.0 and extra.size() < 2:
							extra.append(m.position)
					while extra.size() < 2:
						extra.append(at + Vector2.from_angle(randf() * TAU) * 90.0)
					p._srv_log("%s's Meteor Shower calls 2 more meteors" % p.display_name)
					for e in extra:
						var ep: Vector2 = e
						_fx(p, "telegraph", ep, float(sk["radius"]) * 0.6, Vector2(0.4, 0))
						p._pending.append([0.4, func():
							_fx(p, "burst", ep, float(sk["radius"]) * 0.6)
							for m2 in monsters_in(p, ep, float(sk["radius"]) * 0.6):
								p.hit_monster(m2, float(sk["mult"]) * 0.6, sk)])])
		"shield":
			p._shield = roundi(p.max_hp * float(sk["amount"]))
			p._shield_t = float(sk["duration"])
			p._shield_name = "Stone Skin"
			_fx(p, "ring", pos, 36.0)
			p._srv_log("%s raises Stone Skin (shield %d, %.0fs)" % [p.display_name, p._shield, p._shield_t])
		"taunt":
			var n := 0
			for m in monsters_in(p, pos, float(sk["radius"])):
				m.taunt(p, float(sk["duration"]))
				n += 1
			p._fortify_t = float(sk["duration"])
			_fx(p, "ring", pos, float(sk["radius"]))
			p._srv_log("%s taunted %d monster(s) and is fortified (+50%% defense)" % [p.display_name, n])
		"pulses":
			for i in int(sk["pulses"]):
				p._pending.append([float(sk["interval"]) * i, func():
					if sk.has("stun"):
						p._tlog("tectonic", "%s's Tectonic Fury: Earthquake tremors stun" % p.display_name)
					_fx(p, "ring", p.position, float(sk["radius"]))
					for m in monsters_in(p, p.position, float(sk["radius"])):
						p.hit_monster(m, float(sk["mult"]), sk)])
		_:
			return false
	p._update_status_flags()
	return true
