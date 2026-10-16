extends Node2D
## One zone: its map, its entities and its own MultiplayerSpawners.
## Every peer builds every zone (same node paths everywhere), but each entity's
## MultiplayerSynchronizer has a visibility filter so the server only spawns /
## syncs it to peers whose player is in this zone. Clients therefore only ever
## receive the players, monsters, loot and projectiles of their current zone.

const PlayerScript := preload("res://scripts/player.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")

var zone_id := "meadow"
var info: Dictionary = {}
var main: Node
var map: ZoneMap
var entities: Node2D
var players_root: Node2D
var monsters_root: Node2D
var loot_root: Node2D
var proj_root: Node2D
var _counter := 0
var _pack_counter := 0
var elite_total := 0          # (dungeon) elite packs spawned - for the "slay every elite" bonus objective
var _rng := RandomNumberGenerator.new()
var map_portal_root: Node2D     # (town) visuals of open dungeon portals
var map_portals: Array = []     # (town) [{id, pos, owner, text}] - kept in sync by Instances


func setup(id: String, main_ref: Node) -> void:
	zone_id = id
	info = Zones.info(id)
	main = main_ref
	name = id
	position = Vector2(Zones.index_of(id) * Zones.OFFSET_STEP, 0)
	_rng.seed = hash(id) + Time.get_ticks_usec()

	map = ZoneMap.new()
	map.name = "Map"
	map.build(id)
	add_child(map)
	var dun: Dictionary = info.get("dungeon", {})
	if not dun.is_empty():
		var tn: Array = Dungeons.THEMES[dun["theme"]]["tint"]
		map.modulate = Color(tn[0], tn[1], tn[2])

	for p in info["portals"]:
		var vis := PortalVisual.new()
		var r: Rect2i = p["rect"]
		vis.position = Vector2(r.position * Zones.TILE) + Vector2(r.size * Zones.TILE) / 2.0
		vis.size = Vector2(r.size * Zones.TILE)
		var to := Zones.info(p["to"])
		vis.text = "%s\n(Lv %s)" % [to["name"], to["levels"]]
		if not dun.is_empty():
			vis.text = "Portal back to\nSunny Meadow"
		add_child(vis)

	if info.has("blacksmith"):
		var bs := BlacksmithVisual.new()
		bs.position = map.cell_pos(info["blacksmith"])
		add_child(bs)
	if info.has("map_device"):
		var md := NpcVisual.new()
		md.kind = "device"
		md.position = map.cell_pos(info["map_device"])
		add_child(md)
		var mc := NpcVisual.new()
		mc.kind = "merchant"
		mc.position = map.cell_pos(info["merchant"])
		add_child(mc)
	if info.has("broker"):
		var br := NpcVisual.new()
		br.kind = "broker"
		br.position = map.cell_pos(info["broker"])
		add_child(br)
	if info.has("map_device"):
		map_portal_root = Node2D.new()
		map_portal_root.name = "MapPortals"
		add_child(map_portal_root)

	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	loot_root = _container("Loot", false)
	players_root = _container("Players", true)
	monsters_root = _container("Monsters", true)
	proj_root = _container("Projectiles", false)
	loot_root.z_index = 0   # above the ground tiles, below players (y-sorted container sits at y 0)
	proj_root.z_index = 5

	_spawner("PlayerSpawner", players_root, _spawn_player)
	_spawner("MonsterSpawner", monsters_root, _spawn_monster)
	_spawner("LootSpawner", loot_root, _spawn_loot)
	_spawner("ProjectileSpawner", proj_root, _spawn_projectile)


func _container(n: String, ysort: bool) -> Node2D:
	var c := Node2D.new()
	c.name = n
	c.y_sort_enabled = ysort
	entities.add_child(c)
	return c


func _spawner(n: String, root: Node, fn: Callable) -> void:
	var s := MultiplayerSpawner.new()
	s.name = n
	add_child(s)
	s.spawn_path = NodePath("../Entities/" + str(root.name))
	s.spawn_function = fn
	set(n.to_snake_case(), s)


var player_spawner: MultiplayerSpawner
var monster_spawner: MultiplayerSpawner
var loot_spawner: MultiplayerSpawner
var projectile_spawner: MultiplayerSpawner


## Visibility filter for every entity of this zone (evaluated on the server).
func _peer_in_zone(peer: int) -> bool:
	return main.peer_zone.get(peer, "") == zone_id


func _attach_filter(node: Node) -> void:
	var sync := node.get_node_or_null("Sync") as MultiplayerSynchronizer
	if sync:
		sync.add_visibility_filter(_peer_in_zone)


# ---------------------------------------------------------------- spawn functions (all peers)

func _spawn_player(data: Variant) -> Node:
	var p := PlayerScript.new()
	p.zone = self
	p.setup(int(data["id"]), str(data["name"]), data["pos"], {"class": str(data.get("class", "metal"))})
	_attach_filter(p)
	if multiplayer.is_server():
		p.apply_character(main.take_pending_character(p.peer_id))
		p.account_key = str(main.peer_accounts.get(p.peer_id, ""))
	return p


func _spawn_monster(data: Variant) -> Node:
	var m := MonsterScript.new()
	m.zone = self
	m.setup(int(data["id"]), str(data["type"]), int(data["level"]), data["pos"], int(data.get("pack", -1)), bool(data.get("temp", false)),
		{"el": str(data.get("el", "")), "elite": str(data.get("elite", ""))})
	_attach_filter(m)
	return m


func _spawn_loot(data: Variant) -> Node:
	var l := PickupScript.new()
	l.zone = self
	l.setup(int(data["id"]), str(data["item"]), int(data["count"]), data["pos"], data.get("inst", {}))
	_attach_filter(l)
	return l


func _spawn_projectile(data: Variant) -> Node:
	var pr := ProjectileScript.new()
	pr.zone = self
	pr.setup(int(data["id"]), data["pos"], data["vel"], str(data["kind"]))
	_attach_filter(pr)
	return pr


# ---------------------------------------------------------------- server API

## Entity ids are unique across ALL zones (shared counter), so a target id sent by a
## client can never silently match a different monster in another zone.
static var _global_counter := 0

func next_id() -> int:
	_global_counter += 1
	_counter = _global_counter
	return _counter


## Cells monsters should not spawn near (respawn point and portals).
func avoid_cells() -> Array:
	var a: Array = [info["respawn"]]
	if info.has("blacksmith"):
		a.append(info["blacksmith"])
	if info.has("map_device"):
		a.append(info["map_device"])
		a.append(info["merchant"])
	if info.has("broker"):
		a.append(info["broker"])
	for p in info["portals"]:
		a.append(p["rect"].get_center())
		a.append(p["arrive"])
	return a


func spawn_initial_monsters() -> void:
	for g in info["monsters"]:
		var pack_size := int(g.get("pack", 1))
		var groups := int(g["count"])
		for i in groups:
			var lv := _rng.randi_range(int(g["lv"][0]), int(g["lv"][1]))
			var base := map.random_open_position(_rng, avoid_cells())
			_pack_counter += 1
			for k in pack_size:
				var pos := base
				if k > 0:
					pos = map.spot_near(map.local_to_map(base), _rng, 28.0)
				spawn_monster(str(g["type"]), lv, pos, _pack_counter if pack_size > 1 else -1, false)
	var boss: Dictionary = info.get("boss", {})
	if not boss.is_empty():
		spawn_monster(str(boss["type"]), int(boss["level"]), map.cell_pos(boss["cell"]), -1, false)
		main.log_server("[%s] boss %s spawned" % [zone_id, Monsters.info(boss["type"])["name"]])


func spawn_monster(type: String, level: int, pos: Vector2, pack: int, temp: bool, opts: Dictionary = {}) -> Node:
	var data := {"id": next_id(), "type": type, "level": level, "pos": pos, "pack": pack, "temp": temp}
	var dun: Dictionary = info.get("dungeon", {})
	if not dun.is_empty():
		data["el"] = dun["theme"]   # everything in a dungeon shares its element
		data["temp"] = true         # nothing respawns inside an instance
	for k in opts:
		data[k] = opts[k]
	return monster_spawner.spawn(data)


func is_dungeon() -> bool:
	return info.has("dungeon")


## Value of a map modifier in this zone (0 outside dungeons).
func dungeon_mod(stat: String) -> float:
	return float(info.get("dungeon", {}).get("mods", {}).get(stat, 0.0))


## Server: fill a fresh dungeon instance with packs, elites and the boss.
func spawn_dungeon() -> void:
	var d: Dictionary = info["dungeon"]
	var th: Dictionary = Dungeons.THEMES[d["theme"]]
	var tier := int(d["tier"])
	var lv: int = Dungeons.level(tier)
	var rooms: Array = d["rooms"]
	var order: Array = d["order"]
	var pack_mult := 1.0 + dungeon_mod("map_packs") / 100.0
	var packs := 0
	var placed: Array = []
	for i in range(1, order.size() - 1):    # every room except the start and the boss room
		var rect: Rect2i = rooms[order[i]]
		var n := maxi(1, roundi((1.0 + rect.get_area() / 60.0) * pack_mult * _rng.randf_range(0.8, 1.2)))
		for k in n:
			placed.append([rect, -1])
	var afx: Dictionary = d.get("afx", {})
	var elites := 1 + tier / 4 + int(dungeon_mod("map_elites")) + int(afx.get("elites", 0.0))
	for k in mini(elites, placed.size()):
		placed[_rng.randi() % placed.size()][1] = 1
	var n_elite := 0
	for pk in placed:
		var rect: Rect2i = pk[0]
		var cell := _room_cell(rect)
		if cell == Vector2i(-1, -1):
			continue
		var type: String = th["pool"][_rng.randi() % th["pool"].size()]
		var size := _rng.randi_range(2, 4)
		_pack_counter += 1
		packs += 1
		var is_elite: bool = pk[1] == 1
		for m in size:
			var opts := {}
			if is_elite and m == 0:
				opts["elite"] = Dungeons.ELITE_MODS[_rng.randi() % Dungeons.ELITE_MODS.size()]
				n_elite += 1
			spawn_monster(type, lv + (1 if is_elite and m == 0 else 0), map.spot_near(cell, _rng, 26.0), _pack_counter, true, opts)
	var bt: String = th["boss"]
	spawn_monster(bt, lv + 2, map.cell_pos(d["boss_cell"]), -1, true)
	var boss: Node = monsters_root.get_child(monsters_root.get_child_count() - 1)
	elite_total = n_elite
	var anode := Atlas.node(str(d.get("node", "")))
	if anode.get("guardian", false) or anode.get("pinnacle", false):
		var mult := 3.0 if anode.get("pinnacle", false) else 2.0
		boss.max_hp = roundi(boss.max_hp * mult)
		boss.hp = boss.max_hp
		boss._dmg_mult *= 1.25 if anode.get("pinnacle", false) else 1.15
		main.log_server("[%s] %s boss of %s: x%.1f life, stronger hits" % [zone_id, "PINNACLE" if anode.get("pinnacle", false) else "GUARDIAN", anode["name"], mult])
	main.log_server("[%s] dungeon %s T%d (lv %d, seed %d) populated: %d packs (%d elite), %d monsters, boss %s hp %d (base %d) dmg x%.2f speed x%.2f def %d | mods %s" % [zone_id,
		Dungeons.theme_name(d["theme"]), tier, lv, int(d["seed"]), packs, n_elite, monsters_root.get_child_count(), Monsters.info(bt)["name"],
		boss.max_hp, Monsters.max_hp(bt, lv + 2), boss._dmg_mult, boss._spd_mult, boss.defense, d["mods"]])


func _room_cell(rect: Rect2i) -> Vector2i:
	for i in 30:
		var c := Vector2i(_rng.randi_range(rect.position.x + 1, rect.end.x - 2), _rng.randi_range(rect.position.y + 1, rect.end.y - 2))
		if map.is_reachable(c):
			return c
	return Vector2i(-1, -1)


## Server: every monster death (after its loot) - dungeons track their boss.
func on_monster_died(m: Node, killer: Node) -> void:
	if is_dungeon() and main.instances:
		main.instances.on_monster_died(self, m, killer)


func spawn_projectile(pos: Vector2, vel: Vector2, dmg: int, kind: String, source: String, element: String = "") -> void:
	var pr: Node = projectile_spawner.spawn({"id": next_id(), "pos": pos, "vel": vel, "kind": kind})
	pr.damage = dmg
	pr.source = source
	pr.element = element


## A projectile fired by a player skill / ranged basic attack (hits monsters).
func spawn_player_projectile(pos: Vector2, vel: Vector2, kind: String, shooter: Node, sk: Dictionary) -> void:
	var pr: Node = projectile_spawner.spawn({"id": next_id(), "pos": pos, "vel": vel, "kind": kind})
	pr.setup_player(shooter, sk)


func spawn_pickup(item: String, count: int, pos: Vector2, inst: Dictionary = {}) -> void:
	var off := Vector2(_rng.randf_range(-22, 22), _rng.randf_range(-16, 16))
	var p := pos + off
	if not map.is_walkable_pos(p):
		p = pos
	loot_spawner.spawn({"id": next_id(), "item": item, "count": count, "pos": p, "inst": inst})


## World position of the blacksmith (Sunny Meadow only), or INF.
func blacksmith_pos() -> Vector2:
	if info.has("blacksmith"):
		return map.cell_pos(info["blacksmith"])
	return Vector2.INF


## Server: roll the loot table of a monster type.
func drop_loot(pos: Vector2, type: String, level: int, killer: Node = null, src: Node = null) -> void:
	var d := Monsters.info(type)
	if d.get("xp_mult", 1.0) < 1.0 and d["loot"].is_empty():
		return   # summoned adds drop nothing
	var boss: bool = d.get("boss", false)
	var gold := _rng.randi_range(level, level * 3) * (12 if boss else 1)
	if main.debug_loot:
		gold += 5
	# the killer's farming stats (passives + gear affixes, via Stats.gather) + the monster's own
	var quantity := 0.0
	var rarity := 0.0
	var gold_find := 0.0
	var cls := ""
	if killer and is_instance_valid(killer) and "tmods" in killer:
		quantity = killer.tm("item_quantity")
		rarity = killer.tm("item_rarity")
		gold_find = killer.tm("gold_find")
		cls = killer.class_id
	# dungeon: the ticket's map modifiers + the killer's atlas bonus; elites are richer
	var map_q := 0.0
	var map_r := 0.0
	var afx := {}
	if is_dungeon():
		map_q = float(info["dungeon"].get("iiq", 0.0))
		map_r = float(info["dungeon"].get("iir", 0.0))
		if killer and is_instance_valid(killer) and "atlas" in killer:
			map_q += Dungeons.atlas_iiq(killer.atlas)
		# the run owner's atlas passives (fixed when the ticket was opened)
		afx = info["dungeon"].get("afx", {})
		map_q += float(afx.get("iiq", 0.0))
		map_r += float(afx.get("iir", 0.0))
	var is_elite: bool = src != null and is_instance_valid(src) and str(src.get("elite")) != ""
	if is_elite:
		map_q += 40.0
		map_r += 100.0
	quantity += map_q
	rarity += map_r
	gold = roundi(gold * (1.0 + gold_find / 100.0))
	spawn_pickup("gold", gold, pos)
	var dropped: Array = ["gold x%d" % gold]
	var ilvl := Gear.monster_ilvl(d, level)
	var notable := false
	var drops := Gear.roll_monster_loot(d, level, quantity, rarity, _rng, 3.0 if main.debug_loot else 1.0, cls)
	var extras := Atlas.roll_extras(afx, boss, _rng)
	for k in int(extras["loot_rolls"]):
		drops.append_array(Gear.roll_monster_loot(d, level, quantity, rarity, _rng, 1.0, cls))
	for orb in extras["orbs"]:
		drops.append([orb, 1, {}])
	# dungeon tickets: the atlas sustain loop (tougher overworld monsters drop the odd T1)
	var tchance := 0.0
	var ttier := 1
	if is_dungeon() and not boss:
		ttier = int(info["dungeon"]["tier"])
		tchance = Atlas.ticket_chance(0.15 if is_elite else 0.03, quantity, afx) * (3.0 if main.debug_loot else 1.0)
	elif not is_dungeon() and level >= 6 and not boss:
		tchance = 0.01 * (1.0 + quantity / 100.0) * (3.0 if main.debug_loot else 1.0)
	if tchance > 0.0 and _rng.randf() < tchance:
		var t: Dictionary
		if is_dungeon():
			var here := str(info["dungeon"].get("node", ""))
			if here == "":
				here = Atlas.snap(str(info["dungeon"]["theme"]), ttier)
			var tn := Atlas.roll_drop_node(here, _rng, float(afx.get("tt", 0.0)))
			t = Dungeons.roll_ticket(int(Atlas.node(tn)["tier"]), rarity, _rng, str(Atlas.node(tn)["theme"]))
			if t.get("rarity") != "unique":
				t["node"] = tn
		else:
			t = Dungeons.roll_ticket(1, rarity, _rng)
			if t.get("rarity") != "unique":
				t["node"] = Atlas.snap(Dungeons.theme_of(t), 1)
		drops.append([str(t["base"]), 1, t])
	for drop in drops:
		var inst: Dictionary = drop[2]
		spawn_pickup(drop[0], drop[1], pos, inst)
		if inst.is_empty():
			dropped.append("%s x%d" % [drop[0], drop[1]])
		else:
			dropped.append(Gear.summary(inst))
			notable = notable or inst["rarity"] in ["rare", "unique"]
	if boss or main.debug_loot or notable or is_dungeon():
		var bonus := ""
		if quantity + rarity + gold_find > 0.0:
			bonus = " (killer %s: +%d%% quantity, +%d%% rarity, +%d%% gold)" % [killer.display_name, roundi(quantity), roundi(rarity), roundi(gold_find)]
		var mapnote := ""
		if map_q + map_r > 0.0:
			mapnote = ", map/elite iiq +%d%% iir +%d%%" % [roundi(map_q), roundi(map_r)]
		if int(extras["loot_rolls"]) > 0 or not extras["orbs"].is_empty():
			mapnote += ", atlas passives: +%d extra loot roll(s), +%d bonus currency" % [int(extras["loot_rolls"]), extras["orbs"].size()]
		main.log_server("[%s] %s dropped: %s%s | monster lv %d -> ilvl %d, monster iiq %d%% iir %d%%%s" % [zone_id,
			src.display_name if src and is_instance_valid(src) else d["name"], ", ".join(dropped), bonus,
			level, ilvl, int(d.get("iiq", 0)), int(d.get("iir", 0)), mapnote])


func nearest_player(pos: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for p in players_root.get_children():
		if p.dead or p.is_queued_for_deletion():
			continue
		var d: float = p.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func portal_at(local_pos: Vector2) -> Dictionary:
	var cell := map.local_to_map(local_pos)
	for p in info["portals"]:
		if (p["rect"] as Rect2i).has_point(cell):
			return p
	return {}


## Peers whose player is currently in this zone (server only).
func peers() -> Array:
	var out: Array = []
	var connected := multiplayer.get_peers()
	for pid in main.peer_zone:
		# skip peers whose connection already dropped (their node is removed a moment later)
		if main.peer_zone[pid] == zone_id and (pid == multiplayer.get_unique_id() or connected.has(pid)):
			out.append(pid)
	return out


# ---------------------------------------------------------------- portal visual

class PortalVisual extends Node2D:
	var size := Vector2(64, 128)
	var text := ""
	var _t := 0.0
	var _label: Label

	func _ready() -> void:
		z_index = -1
		_label = Label.new()
		_label.text = text
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size = Vector2(200, 36)
		_label.position = Vector2(-100, -size.y / 2.0 - 40.0)
		if size.x > size.y:   # horizontal gate at the top/bottom edge
			_label.position = Vector2(-100, size.y / 2.0 + 4.0) if position.y < 200.0 else Vector2(-100, -size.y / 2.0 - 40.0)
		_label.z_index = 30
		_label.add_theme_font_size_override("font_size", 12)
		_label.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
		add_child(_label)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(-size / 2.0, size)
		draw_rect(r, Color(0.45, 0.2, 0.8, 0.25 + 0.1 * sin(_t * 3.0)))
		draw_rect(r, Color(0.75, 0.55, 1.0, 0.8), false, 2.0)
		for i in 6:
			var ph := _t * 1.5 + i * 1.05
			var p := Vector2(sin(ph * 1.3) * size.x * 0.35, cos(ph) * size.y * 0.35)
			draw_circle(p, 2.5, Color(0.9, 0.8, 1.0, 0.8))


# ---------------------------------------------------------------- blacksmith station (Sunny Meadow)

class BlacksmithVisual extends Node2D:
	var _t := 0.0

	func _ready() -> void:
		z_index = 0
		for spec in [["res://assets/anvil.png", Vector2(0, 6)], ["res://assets/blacksmith.png", Vector2(-26, -4)], ["res://assets/chest.png", Vector2(28, 4)]]:
			var s := Sprite2D.new()
			s.texture = load(spec[0])
			s.position = spec[1]
			add_child(s)
		var l := Label.new()
		l.text = "Blacksmith\n(E: craft / sell / stash)"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(200, 36)
		l.position = Vector2(-100, -52)
		l.z_index = 30
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		add_child(l)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2(0, 14), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, 46.0, Color(0, 0, 0, 0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var spark := fmod(_t, 1.6)
		if spark < 0.35:   # anvil sparks
			for i in 4:
				var a := -PI / 2.0 + (i - 1.5) * 0.5
				draw_circle(Vector2(0, -2) + Vector2.from_angle(a) * spark * 40.0, 1.5, Color(1, 0.8, 0.3, 1.0 - spark * 2.5))


# ---------------------------------------------------------------- town: dungeon portals (all peers)

## Replaces the visuals of the open dungeon portals in town (data from Instances).
func set_map_portals(list: Array) -> void:
	map_portals = list
	if map_portal_root == null:
		return
	for c in map_portal_root.get_children():
		c.queue_free()
	for p in list:
		var v := PortalVisual.new()
		v.size = Vector2(44, 56)
		v.position = p["pos"]
		v.text = str(p["text"])
		map_portal_root.add_child(v)


## (server) The open dungeon portal at this town position, or {}.
func map_portal_at(local_pos: Vector2) -> Dictionary:
	for p in map_portals:
		if (p["pos"] as Vector2).distance_to(local_pos) <= 24.0:
			return p
	return {}


func map_device_pos() -> Vector2:
	return map.cell_pos(info["map_device"]) if info.has("map_device") else Vector2.INF


func broker_pos() -> Vector2:
	return map.cell_pos(info["broker"]) if info.has("broker") else Vector2.INF


func merchant_pos() -> Vector2:
	return map.cell_pos(info["merchant"]) if info.has("merchant") else Vector2.INF


# ---------------------------------------------------------------- town NPCs: Map Device + Ticket Merchant

class NpcVisual extends Node2D:
	var kind := "device"
	var _t := 0.0

	func _ready() -> void:
		z_index = 0
		var l := Label.new()
		if kind == "merchant":
			var s := Sprite2D.new()
			s.texture = load("res://assets/merchant.png")
			s.position = Vector2(0, -6)
			add_child(s)
			var st := Sprite2D.new()
			st.texture = load("res://assets/items/ticket_wood.png")
			st.position = Vector2(20, 2)
			add_child(st)
			l.text = "Ticket Merchant\n(E: buy tickets  -  M: atlas)"
		elif kind == "broker":
			var s := Sprite2D.new()
			s.texture = load("res://assets/merchant.png")
			s.modulate = Color(0.75, 1.0, 0.8)
			s.flip_h = true
			s.position = Vector2(0, -6)
			add_child(s)
			var gi := Sprite2D.new()
			gi.texture = load("res://assets/items/gold.png") if ResourceLoader.exists("res://assets/items/gold.png") else null
			gi.position = Vector2(-20, 2)
			add_child(gi)
			l.text = "Trade Broker\n(E: player market)"
		else:
			l.text = "Map Device\n(E: open a dungeon ticket)"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(220, 36)
		l.position = Vector2(-110, -56)
		l.z_index = 30
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0) if kind == "device" else (Color(0.6, 1.0, 0.7) if kind == "broker" else Color(1.0, 0.85, 0.55)))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		add_child(l)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 34.0 if kind == "device" else 20.0, Color(0, 0, 0, 0.2))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if kind != "device":
			return
		# a stone ring with the five element stones around it, slowly glowing
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, 26.0, Color(0.35, 0.33, 0.38))
		draw_circle(Vector2.ZERO, 19.0, Color(0.12, 0.1, 0.18))
		draw_circle(Vector2.ZERO, 15.0, Color(0.5, 0.3, 0.9, 0.35 + 0.15 * sin(_t * 2.5)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 5:
			var a := -PI / 2.0 + TAU * i / 5.0 + _t * 0.3
			var p := Vector2(cos(a) * 26.0, 2.0 + sin(a) * 26.0 * 0.55)
			draw_circle(p + Vector2(0, -4), 5.0, Classes.color(Classes.ELEMENTS[i]))
			draw_circle(p + Vector2(0, -5), 2.0, Color(1, 1, 1, 0.6))
