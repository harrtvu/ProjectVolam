class_name ZoneMap
extends TileMap
## Tile map for one zone, generated from a fixed seed so every peer builds the
## exact same map. Art: Kenney CC0 packs (see CREDITS.md), atlas built by
## tools/build_assets.py. Tile constants live in the generated scripts/tiles.gd.

const W := Zones.W      # instance / old-core size; the generators of the old layouts use these
const H := Zones.H
const TILE := Zones.TILE

var zone_id := "meadow"
var w := W              # real size of this map in tiles (200x128 for overworld zones)
var h := H
## Overworld only: generated monster sites. [{cell, depth (0 entrance .. 1 farthest), kind, spec}]
## kind: "pack" | "camp" | "elite" | "patrol" | "" (empty clearing). Deterministic on every peer.
var sites: Array = []
var _o := Vector2i.ZERO   # offset added by _put/_at while an old 64x40 layout is painted into its core
var reachable := {}   # Vector2i -> true, walkable cells connected to the zone's respawn point
var _reachable_list: Array[Vector2i] = []
var _r := RandomNumberGenerator.new()

static var _shared_tileset: TileSet


func build(id: String) -> void:
	zone_id = id
	var sz := Zones.size_of(id)
	w = sz.x
	h = sz.y
	sites.clear()
	tile_set = _get_tileset()
	_r.seed = 1337 + Zones.index_of(id) * 101
	var zi := Zones.info(id)
	if zi.has("dungeon"):
		_r.seed = int(zi["dungeon"]["seed"])
		_gen_dungeon(zi["dungeon"])
	elif zi.has("hideout"):
		_r.seed = 4242
		_gen_hideout(zi["hideout"])
	else:
		_gen_overworld(id)
	for p in Zones.info(id)["portals"]:
		_fill_rect(p["rect"], _portal_floor())
	_compute_reachable()


# ---------------------------------------------------------------- queries

func is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
		return false
	return not (get_cell_atlas_coords(0, cell) in Tiles.SOLID)


func is_walkable_pos(pos: Vector2) -> bool:
	return is_walkable(local_to_map(pos))


const SEE_THROUGH := [Tiles.WATER, Tiles.WATER2, Tiles.F_WATER]

## Does this tile block sight / projectiles? (walls, trees, rocks... but not water)
func blocks_sight(pos: Vector2) -> bool:
	var cell := local_to_map(pos)
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
		return true
	var a := get_cell_atlas_coords(0, cell)
	return a in Tiles.SOLID and not (a in SEE_THROUGH)


## Line of sight between two points (zone coordinates), sampled every 8 px.
func has_los(a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / 8.0))
	for i in range(1, n):
		if blocks_sight(a.lerp(b, float(i) / n)):
			return false
	return true


func is_reachable(cell: Vector2i) -> bool:
	return reachable.has(cell)


func cell_pos(cell: Vector2i) -> Vector2:
	return map_to_local(cell)


func world_size_px() -> Vector2i:
	return Vector2i(w * TILE, h * TILE)


## A spot near `cell` (used for respawn / arrival).
func spot_near(cell: Vector2i, r: RandomNumberGenerator, spread := 40.0) -> Vector2:
	for i in 20:
		var p := map_to_local(cell) + Vector2(r.randf_range(-spread, spread), r.randf_range(-spread, spread))
		if is_walkable_pos(p):
			return p
	return map_to_local(cell)


## Random reachable spot with open space around it, away from `avoid` cells.
func random_open_position(r: RandomNumberGenerator, avoid: Array) -> Vector2:
	for i in 400:
		var cell: Vector2i = _reachable_list[r.randi() % _reachable_list.size()]
		var ok := true
		for a in avoid:
			if Vector2(cell).distance_to(Vector2(a)) < 8.0:
				ok = false
				break
		if not ok:
			continue
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if not is_walkable(cell + Vector2i(dx, dy)):
					ok = false
		if ok:
			return map_to_local(cell)
	return map_to_local(_reachable_list[0])


## The reachable spot closest to `pos` (searched in growing rings), else next to `fallback`.
func nearest_reachable_pos(pos: Vector2, fallback: Vector2i) -> Vector2:
	var c := local_to_map(pos)
	c = Vector2i(clampi(c.x, 0, w - 1), clampi(c.y, 0, h - 1))
	for r in 16:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and reachable.has(c + Vector2i(dx, dy)):
					return map_to_local(c + Vector2i(dx, dy))
	return map_to_local(fallback)


## 1 pixel per tile picture of the map (minimap / zone map, scripts/minimap.gd).
func overview_image() -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		for y in h:
			var a := get_cell_atlas_coords(0, Vector2i(x, y))
			var c := Color(0.42, 0.62, 0.3)   # grass
			if a in [Tiles.WATER, Tiles.WATER2, Tiles.F_WATER]:
				c = Color(0.2, 0.4, 0.75)
			elif a in Tiles.TREES:
				c = Color(0.12, 0.3, 0.14) if a.x < 50 else Color(0.35, 0.45, 0.4)
			elif a in Tiles.SOLID:
				c = Color(0.18, 0.17, 0.2) if a.x >= 37 and a.x < 50 else Color(0.45, 0.43, 0.45)
			elif a.x >= Tiles.PATH_TL.x and a.x <= Tiles.PATH_BR.x or a.x >= Tiles.F_PATH_TL.x and a.x <= Tiles.F_PATH_BR.x or a == Tiles.S_SNOW3:
				c = Color(0.78, 0.66, 0.45)
			elif a.x >= 19 and a.x < 28:
				c = Color(0.26, 0.45, 0.22)
			elif a == Tiles.C_SAND:
				c = Color(0.75, 0.65, 0.42)
			elif a.x >= 37 and a.x < 50:
				c = Color(0.48, 0.45, 0.42)
			elif a == Tiles.S_ICE:
				c = Color(0.7, 0.85, 0.95)
			elif a.x >= 50:
				c = Color(0.88, 0.9, 0.95)
			elif a == Tiles.FLOOR:
				c = Color(0.6, 0.55, 0.48)
			img.set_pixel(x, y, c)
	return img


func _compute_reachable() -> void:
	reachable.clear()
	_reachable_list.clear()
	var start: Vector2i = Zones.info(zone_id)["respawn"]
	var queue: Array[Vector2i] = [start]
	reachable[start] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		_reachable_list.append(c)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not reachable.has(n) and is_walkable(n):
				reachable[n] = true
				queue.append(n)


## Builds an AStarGrid2D over this map (used by the test bots to navigate).
func make_astar() -> AStarGrid2D:
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, w, h)
	a.cell_size = Vector2(TILE, TILE)
	a.offset = Vector2(TILE / 2.0, TILE / 2.0)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.update()
	for x in w:
		for y in h:
			if not is_walkable(Vector2i(x, y)):
				a.set_point_solid(Vector2i(x, y), true)
	return a


# ---------------------------------------------------------------- tileset

func _get_tileset() -> TileSet:
	if _shared_tileset:
		return _shared_tileset
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	var src := TileSetAtlasSource.new()
	# art test: same atlas layout, Whisperwood (F_*) cells redrawn from Ninja Adventure -> collision unchanged
	src.texture = ArtTest.tex("tiles.png") if ArtTest.tex("tiles.png") else load("res://assets/tiles.png")
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	for i in Tiles.COUNT:
		src.create_tile(Vector2i(i, 0))
	var h := TILE / 2.0
	var square := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var trunk := PackedVector2Array([Vector2(-9, -12), Vector2(9, -12), Vector2(9, h), Vector2(-9, h)])
	for solid in Tiles.SOLID:
		var td := src.get_tile_data(solid, 0)
		td.add_collision_polygon(0)
		# trees get a slightly smaller box so paths between them feel fair
		td.set_collision_polygon_points(0, 0, trunk if solid in Tiles.TREES else square)
	_shared_tileset = ts
	return ts


# ---------------------------------------------------------------- helpers

func _put(c: Vector2i, t: Vector2i) -> void:
	c += _o
	if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h:
		set_cell(0, c, 0, t)


func _at(c: Vector2i) -> Vector2i:
	return get_cell_atlas_coords(0, c + _o)


func _fill_rect(r: Rect2i, t: Vector2i) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			_put(Vector2i(x, y), t)


func _ellipse(center: Vector2, radius: Vector2, tiles: Array) -> void:
	for x in W:
		for y in H:
			var d := Vector2((x - center.x) / radius.x, (y - center.y) / radius.y)
			if d.length_squared() <= 1.0:
				_put(Vector2i(x, y), tiles[_r.randi() % tiles.size()])


func _border(t: Array, thickness := 2) -> void:
	for x in W:
		for y in H:
			if x < thickness or y < thickness or x >= W - thickness or y >= H - thickness:
				_put(Vector2i(x, y), t[_r.randi() % t.size()])


## Carves a `width`-wide line between cells (Bresenham-ish walk).
func _carve(a: Vector2i, b: Vector2i, t: Vector2i, width := 2) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in steps + 1:
		var p := Vector2(a).lerp(Vector2(b), float(i) / maxf(1.0, float(steps)))
		var c := Vector2i(roundi(p.x), roundi(p.y))
		for dx in width:
			for dy in width:
				_put(c + Vector2i(dx, dy), t)


func _carve_path(points: Array, t: Vector2i, width := 2) -> void:
	for i in points.size() - 1:
		_carve(points[i], points[i + 1], t, width)


func _gen_hideout(h: Dictionary) -> void:
	var th: Dictionary = Hideouts.THEMES.get(str(h.get("theme", "meadow")), Hideouts.THEMES["meadow"])
	var wall := Hideouts.tile(th["wall"])
	var outer := Tiles.WALL if th["wall"] != "TREE" else Tiles.TREE
	for x in W:
		for y in H:
			_put(Vector2i(x, y), outer)
	var floors: Array = []
	for n in th["floor"]:
		floors.append(Hideouts.tile(n))
	var room: Rect2i = Hideouts.ROOM
	for x in range(room.position.x - 1, room.end.x + 1):
		for y in range(room.position.y - 1, room.end.y + 1):
			var c := Vector2i(x, y)
			_put(c, floors[_r.randi() % floors.size()] if room.has_point(c) else wall)


func _portal_floor() -> Vector2i:
	if Zones.is_hideout(zone_id):
		return Hideouts.tile(Hideouts.THEMES.get(str(Zones.info(zone_id)["hideout"].get("theme", "meadow")), Hideouts.THEMES["meadow"])["floor"][0])
	if Zones.is_dungeon(zone_id):
		return Dungeons.tile(Dungeons.THEMES[Zones.info(zone_id)["dungeon"]["theme"]]["floor"][0])
	match zone_id:
		"forest": return Tiles.F_PATH_C
		"crypt": return Tiles.C_FLOOR
		"frost": return Tiles.S_SNOW
	return Tiles.PATH_C


## Replace "centre" path tiles with the right edge/corner pieces.
func _autotile(first: Vector2i) -> void:
	var lo := first.x
	var is_path := func(c: Vector2i) -> bool:
		var a := _at(c)
		return a.y == 0 and a.x >= lo and a.x < lo + 9
	var pieces := {}
	for x in w:
		for y in h:
			var c := Vector2i(x, y)
			if not is_path.call(c):
				continue
			var col := 1
			var row := 1
			if not is_path.call(c + Vector2i.LEFT):
				col = 0
			elif not is_path.call(c + Vector2i.RIGHT):
				col = 2
			if not is_path.call(c + Vector2i.UP):
				row = 0
			elif not is_path.call(c + Vector2i.DOWN):
				row = 2
			pieces[c] = Vector2i(lo + row * 3 + col, 0)
	for c in pieces:
		_put(c, pieces[c])


# ---------------------------------------------------------------- big overworld zones

## A 200x128 zone: themed outer terrain, the old 64x40 layout painted into its core (entrance area),
## then monster sites (clearings / camps / stone circles / crypt rooms) joined by roads, the boss lair
## and a solid border. Everything comes from _r, so every peer builds the same map.
func _gen_overworld(id: String) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _r.randi()
	noise.frequency = 0.045
	var noise2 := FastNoiseLite.new()
	noise2.seed = _r.randi()
	noise2.frequency = 0.03
	for x in w:
		for y in h:
			_put(Vector2i(x, y), _outer_tile(id, noise.get_noise_2d(x, y), noise2.get_noise_2d(x, y)))
	_o = Zones.core_of(id)
	match id:
		"forest": _gen_forest()
		"crypt": _gen_crypt()
		"frost": _gen_frost()
		_: _gen_meadow()
	_o = Vector2i.ZERO
	_gen_sites(id)
	var thick := 2
	for x in w:
		for y in h:
			if x < thick or y < thick or x >= w - thick or y >= h - thick:
				_put(Vector2i(x, y), _wall_tile(id))
	if id == "meadow":
		_autotile(Tiles.PATH_TL)
	elif id == "forest":
		_autotile(Tiles.F_PATH_TL)


func _outer_tile(id: String, n: float, n2: float) -> Vector2i:
	var roll := _r.randf()
	match id:
		"forest":
			if n2 > 0.5:
				return Tiles.F_WATER
			if n > -0.05 and roll < 0.72 or roll < 0.07:
				return [Tiles.F_PINE, Tiles.F_PINE, Tiles.F_TREE, Tiles.F_OAK, Tiles.F_DEAD][_r.randi() % 5]
			return Tiles.F_GRASS2 if roll < 0.2 else (Tiles.F_MUSHROOM if roll < 0.23 else (Tiles.F_STUMP if roll < 0.24 else Tiles.F_GRASS))
		"crypt":
			if n > 0.28:   # sandy caverns between the halls
				return Tiles.C_SAND if n2 > 0.0 else (Tiles.C_RUBBLE if roll < 0.08 else Tiles.C_FLOOR2)
			return Tiles.C_WALL
		"frost":
			if n2 > 0.48:
				return Tiles.S_ICE
			if n > 0.25 and roll < 0.55 or roll < 0.04:
				return [Tiles.S_PINE, Tiles.S_PINE2, Tiles.S_PINE, Tiles.S_DEAD][_r.randi() % 4]
			if roll < 0.065:
				return Tiles.S_ROCK
			return Tiles.S_SNOW2 if roll < 0.2 else Tiles.S_SNOW
	if n2 > 0.52:
		return Tiles.WATER if roll < 0.8 else Tiles.WATER2
	if n > 0.32 and roll < 0.6 or roll < 0.025:
		return [Tiles.TREE, Tiles.TREE, Tiles.TREE2][_r.randi() % 3]
	return Tiles.FLOWER if roll < 0.08 else (Tiles.GRASS2 if roll < 0.2 else (Tiles.MUSHROOM if roll < 0.205 else Tiles.GRASS))


func _wall_tile(id: String) -> Vector2i:
	match id:
		"forest": return [Tiles.F_PINE, Tiles.F_TREE][_r.randi() % 2]
		"crypt": return Tiles.C_WALL
		"frost": return [Tiles.S_ROCK, Tiles.S_PINE][_r.randi() % 2]
	return Tiles.WALL


func _ground_tile(id: String) -> Vector2i:
	match id:
		"forest": return Tiles.F_GRASS if _r.randf() < 0.85 else Tiles.F_GRASS2
		"crypt": return Tiles.C_FLOOR if _r.randf() < 0.88 else Tiles.C_FLOOR2
		"frost": return Tiles.S_SNOW if _r.randf() < 0.8 else Tiles.S_SNOW2
	return Tiles.GRASS if _r.randf() < 0.85 else Tiles.GRASS2


func _road_tile(id: String) -> Vector2i:
	match id:
		"forest": return Tiles.F_PATH_C
		"crypt": return Tiles.C_FLOOR
		"frost": return Tiles.S_SNOW3
	return Tiles.PATH_C


## Points inside the old core that the outer road network starts from (core coordinates).
const ANCHORS := {
	"meadow": [Vector2i(2, 20), Vector2i(32, 2), Vector2i(32, 37)],
	"forest": [Vector2i(55, 24), Vector2i(43, 29), Vector2i(18, 28)],
	"crypt": [Vector2i(9, 8), Vector2i(31, 4), Vector2i(20, 20)],
	"frost": [Vector2i(14, 20), Vector2i(28, 9), Vector2i(33, 27)],
}


## Picks the monster sites, assigns the zone's group specs to them by depth, carves each site
## (clearing / camp / stone circle / crypt room) and connects everything with roads.
func _gen_sites(id: String) -> void:
	var zi: Dictionary = Zones.info(id)
	var core := Rect2i(Zones.core_of(id), Vector2i(W, H)).grow(3)
	var entrance := Vector2(zi["respawn"])
	var boss_cell: Vector2i = zi["boss"].get("cell", Vector2i(-100, -100))
	var specs: Array = []   # one entry per group to place: spec index
	for i in zi["groups"].size():
		var g: Dictionary = zi["groups"][i]
		if g.get("core", false) or g["kind"] == "guard":
			continue
		for k in int(g["n"]):
			specs.append(i)
	var want := specs.size() + 8
	var cells: Array = []
	for attempt in 6000:
		if cells.size() >= want:
			break
		var c := Vector2i(_r.randi_range(8, w - 9), _r.randi_range(8, h - 9))
		if core.has_point(c) or Vector2(c).distance_to(Vector2(boss_cell)) < 16.0:
			continue
		var ok := true
		for o in cells:
			if Vector2(c).distance_to(Vector2(o)) < 15.0:
				ok = false
				break
		for p in zi["portals"]:
			if Vector2(c).distance_to(Vector2(p["rect"].get_center())) < 14.0:
				ok = false
		if ok:
			cells.append(c)
	var far := 1.0
	for c in cells + [boss_cell]:
		far = maxf(far, entrance.distance_to(Vector2(c)))
	for c in cells:
		sites.append({"cell": c, "depth": entrance.distance_to(Vector2(c)) / far, "kind": "", "spec": -1})
	# deepest groups first (elites / camps want the far sites), then fill the rest
	specs.sort_custom(func(a, b): return float(zi["groups"][a].get("depth", [0, 1])[0]) > float(zi["groups"][b].get("depth", [0, 1])[0]))
	for si in specs:
		var g: Dictionary = zi["groups"][si]
		var dr: Array = g.get("depth", [0.0, 1.0])
		var free: Array = []
		var best := -1
		var best_gap := INF
		for i in sites.size():
			if sites[i]["spec"] != -1:
				continue
			var d: float = sites[i]["depth"]
			if d >= float(dr[0]) and d <= float(dr[1]):
				free.append(i)
			var gap := maxf(float(dr[0]) - d, d - float(dr[1]))
			if gap < best_gap:
				best_gap = gap
				best = i
		var pick: int = free[_r.randi() % free.size()] if not free.is_empty() else best
		if pick >= 0:
			sites[pick]["spec"] = si
			sites[pick]["kind"] = str(g["kind"])
	# carve the sites + boss lair, then roads: each node joins the nearest already-connected one
	for s in sites:
		_carve_site(id, s["cell"], str(s["kind"]))
	if boss_cell.x >= 0:
		_carve_lair(id, boss_cell)
	var connected: Array = []
	for a in ANCHORS[id]:
		connected.append(a + Zones.core_of(id))
	var todo: Array = []
	for s in sites:
		todo.append(s["cell"])
	if boss_cell.x >= 0:
		todo.append(boss_cell)
	while not todo.is_empty():
		var bi := 0
		var bj := 0
		var bd := INF
		for i in todo.size():
			for j in connected.size():
				var d := Vector2(todo[i]).distance_squared_to(Vector2(connected[j]))
				if d < bd:
					bd = d
					bi = i
					bj = j
		_road(id, connected[bj], todo[bi])
		connected.append(todo[bi])
		todo.remove_at(bi)


## A road between two cells with one random bend (crypt: an L-shaped 3-wide corridor).
func _road(id: String, a: Vector2i, b: Vector2i) -> void:
	var t := _road_tile(id)
	if id == "crypt":
		var corner := Vector2i(b.x, a.y) if _r.randf() < 0.5 else Vector2i(a.x, b.y)
		_carve(a, corner, t, 3)
		_carve(corner, b, t, 3)
		return
	var mid := (a + b) / 2 + Vector2i(_r.randi_range(-6, 6), _r.randi_range(-6, 6))
	_carve_path([a, mid, b], t, 2)


func _disc(c: Vector2i, r: float, fn: Callable) -> void:
	for x in range(c.x - ceili(r), c.x + ceili(r) + 1):
		for y in range(c.y - ceili(r), c.y + ceili(r) + 1):
			if Vector2(x - c.x, y - c.y).length() <= r:
				fn.call(Vector2i(x, y))


func _carve_site(id: String, c: Vector2i, kind: String) -> void:
	if id == "crypt":
		var hw := _r.randi_range(5, 7)
		var hh := _r.randi_range(4, 5)
		_floor_rect(Rect2i(c.x - hw, c.y - hh, hw * 2 + 1, hh * 2 + 1))
		for k in 4:   # a few tombs / graves along the walls, pillars in big rooms
			_put(Vector2i(c.x - hw + 1 + k * (hw / 2), c.y - hh + 1), [Tiles.C_TOMB, Tiles.C_GRAVE][k % 2])
		if hw >= 6:
			for dx in [-hw + 2, hw - 2]:
				_put(Vector2i(c.x + dx, c.y + hh - 1), Tiles.C_PILLAR)
	else:
		_disc(c, _r.randf_range(4.5, 6.0), func(p): _put(p, _ground_tile(id)))
	match kind:
		"camp":   # trampled ground, supply barrels around the camp fire (fire drawn by zone.gd)
			var fl := Tiles.C_SAND if id == "crypt" else (Tiles.S_FLOOR if id == "frost" else Tiles.FLOOR)
			_disc(c, 2.6, func(p): _put(p, fl))
			for d in [Vector2i(-3, -2), Vector2i(3, -2), Vector2i(-3, 2), Vector2i(3, 2)]:
				_put(c + d, Tiles.C_BARREL)
		"elite":   # standing stones around the elite
			var st := Tiles.C_PILLAR if id == "crypt" else Tiles.S_ROCK
			for i in 6:
				var a := TAU * i / 6.0
				_put(c + Vector2i(roundi(cos(a) * 4.0), roundi(sin(a) * 3.0)), st)
			_put(c, Tiles.C_ALTAR)
		_:
			var deco: Vector2i = {"forest": Tiles.F_STUMP, "frost": Tiles.S_SNOWMAN, "crypt": Tiles.C_GRAVE}.get(id, Tiles.MUSHROOM)
			if _r.randf() < 0.5:
				_put(c + Vector2i(_r.randi_range(-3, 3), -3), deco)


## Boss lair: a big clearing walled in by the zone's wall tile, with four gates.
func _carve_lair(id: String, c: Vector2i) -> void:
	var wall: Vector2i = {"forest": Tiles.F_DEAD, "crypt": Tiles.C_WALL, "frost": Tiles.S_WALL}.get(id, Tiles.WALL)
	var fl: Vector2i = {"forest": Tiles.F_GRASS2, "crypt": Tiles.C_FLOOR, "frost": Tiles.S_FLOOR}.get(id, Tiles.FLOOR)
	_disc(c, 9.5, func(p): _put(p, wall))
	_disc(c, 8.5, func(p): _put(p, fl))
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for k in range(7, 11):
			for s in [-1, 0, 1]:
				_put(c + d * k + Vector2i(d.y, d.x) * s, fl)
	for i in 8:
		var a := TAU * i / 8.0 + 0.4
		_put(c + Vector2i(roundi(cos(a) * 6.0), roundi(sin(a) * 6.0)), Tiles.C_PILLAR if id == "crypt" else (Tiles.S_ROCK if id == "frost" else Tiles.F_STUMP))


# ---------------------------------------------------------------- Meadow

func _gen_meadow() -> void:
	var spawn := Vector2i(32, 20)
	for x in W:
		for y in H:
			var roll := _r.randf()
			var t := Tiles.GRASS
			if roll < 0.05:
				t = Tiles.FLOWER
			elif roll < 0.14:
				t = Tiles.GRASS2
			elif roll < 0.143:
				t = Tiles.MUSHROOM
			_put(Vector2i(x, y), t)
	for x in range(2, W):
		for dy in [0, 1]:
			_put(Vector2i(x, spawn.y + dy), Tiles.PATH_C)
	for y in range(2, H - 2):
		for dx in [0, 1]:
			_put(Vector2i(spawn.x + dx, y), Tiles.PATH_C)
	_ellipse(Vector2(47, 10), Vector2(8, 5), [Tiles.WATER, Tiles.WATER, Tiles.WATER2])
	_ellipse(Vector2(11, 31), Vector2(4.5, 3), [Tiles.WATER, Tiles.WATER, Tiles.WATER2])
	_ruin(Rect2i(7, 5, 12, 8), Vector2i(12, 12), Tiles.WALL, Tiles.FLOOR)
	_ruin(Rect2i(42, 26, 9, 8), Vector2i(42, 29), Tiles.WALL, Tiles.FLOOR)
	for i in 110:
		var cell := Vector2i(_r.randi_range(2, W - 3), _r.randi_range(2, H - 3))
		if not (_at(cell) in [Tiles.GRASS, Tiles.GRASS2, Tiles.FLOWER, Tiles.MUSHROOM]):
			continue
		if Vector2(cell).distance_to(Vector2(spawn)) < 6.0:
			continue
		if cell.x >= 21 and cell.x <= 39 and cell.y >= 10 and cell.y <= 19:
			continue   # town plaza: Ticket Merchant, Map Device + its portals, blacksmith
		_put(cell, [Tiles.TREE, Tiles.TREE, Tiles.TREE2][_r.randi() % 3])


func _ruin(rect: Rect2i, door: Vector2i, wall: Vector2i, floor_t: Vector2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var edge := x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
			_put(Vector2i(x, y), wall if edge else floor_t)
	_put(door, floor_t)
	if door.y == rect.end.y - 1 or door.y == rect.position.y:
		_put(door + Vector2i(1, 0), floor_t)
	else:
		_put(door + Vector2i(0, 1), floor_t)


# ---------------------------------------------------------------- Whisperwood Forest

func _gen_forest() -> void:
	var trees := [Tiles.F_PINE, Tiles.F_PINE, Tiles.F_TREE, Tiles.F_OAK, Tiles.F_DEAD]
	for x in W:
		for y in H:
			var roll := _r.randf()
			var t := Tiles.F_GRASS
			if roll < 0.34:
				t = trees[_r.randi() % trees.size()]
			elif roll < 0.40:
				t = Tiles.F_GRASS2
			elif roll < 0.42:
				t = Tiles.F_MUSHROOM
			elif roll < 0.43:
				t = Tiles.F_STUMP
			_put(Vector2i(x, y), t)
	# clearings (grass), then winding paths connecting everything
	for c in [[Vector2(50, 9), Vector2(7, 5)], [Vector2(18, 28), Vector2(6, 4)], [Vector2(44, 29), Vector2(7, 5)],
			[Vector2(24, 12), Vector2(5, 4)], [Vector2(8, 10), Vector2(4, 4)], [Vector2(56, 22), Vector2(4, 4)]]:
		_ellipse(c[0], c[1], [Tiles.F_GRASS, Tiles.F_GRASS, Tiles.F_GRASS2, Tiles.F_MUSHROOM])
	var p := Tiles.F_PATH_C
	_carve_path([Vector2i(0, 20), Vector2i(10, 21), Vector2i(18, 18), Vector2i(26, 16), Vector2i(31, 10), Vector2i(31, 0)], p, 2)
	_carve_path([Vector2i(26, 16), Vector2i(36, 15), Vector2i(44, 11), Vector2i(48, 9)], p, 2)
	_carve_path([Vector2i(18, 18), Vector2i(18, 26)], p, 2)
	_carve_path([Vector2i(26, 16), Vector2i(34, 24), Vector2i(42, 28)], p, 2)
	_carve_path([Vector2i(42, 28), Vector2i(54, 24)], p, 2)
	_carve_path([Vector2i(10, 21), Vector2i(8, 12)], p, 2)
	_ellipse(Vector2(12, 33), Vector2(4, 2.5), [Tiles.F_WATER])
	_ellipse(Vector2(57, 33), Vector2(3, 3), [Tiles.F_WATER])


# ---------------------------------------------------------------- Bone Crypt

func _gen_crypt() -> void:
	_fill_rect(Rect2i(0, 0, W, H), Tiles.C_WALL)
	var rooms := [
		Rect2i(26, 29, 13, 9),   # entrance hall (south)
		Rect2i(18, 15, 28, 10),  # great hall
		Rect2i(21, 2, 23, 10),   # boss chamber (north)
		Rect2i(4, 4, 12, 9),     # west ossuary
		Rect2i(4, 26, 13, 9),    # south-west graves
		Rect2i(50, 12, 10, 14),  # east chapel
		Rect2i(50, 29, 10, 7),   # south-east store room
	]
	for r in rooms:
		_floor_rect(r)
	var f := Tiles.C_FLOOR
	_carve(Vector2i(31, 37), Vector2i(31, 39), f, 4)          # south exit
	_carve(Vector2i(31, 24), Vector2i(31, 29), f, 3)          # entrance -> great hall
	_carve(Vector2i(31, 11), Vector2i(31, 15), f, 3)          # great hall -> boss
	_carve(Vector2i(15, 8), Vector2i(21, 8), f, 3)            # west room -> boss chamber
	_carve(Vector2i(9, 12), Vector2i(9, 26), f, 3)            # west room -> graves
	_carve(Vector2i(16, 30), Vector2i(26, 30), f, 3)          # graves -> entrance
	_carve(Vector2i(45, 19), Vector2i(50, 19), f, 3)          # great hall -> chapel
	_carve(Vector2i(54, 25), Vector2i(54, 29), f, 3)          # chapel -> store room
	_carve(Vector2i(59, 19), Vector2i(63, 19), f, 4)          # east exit -> Frostpeak
	# decorations
	for x in range(21, 45, 4):                               # pillars in the great hall
		_put(Vector2i(x, 17), Tiles.C_PILLAR)
		_put(Vector2i(x, 22), Tiles.C_PILLAR)
	for x in range(6, 16, 3):                                # rows of graves
		_put(Vector2i(x, 28), Tiles.C_TOMB)
		_put(Vector2i(x, 32), Tiles.C_GRAVE)
	for x in range(6, 15, 2):
		_put(Vector2i(x, 5), Tiles.C_GRAVE)
	for y in range(14, 25, 3):
		_put(Vector2i(51, y), Tiles.C_TOMB)
		_put(Vector2i(58, y), Tiles.C_TOMB)
	for c in [Vector2i(51, 30), Vector2i(52, 30), Vector2i(58, 34), Vector2i(57, 34), Vector2i(27, 30), Vector2i(37, 36)]:
		_put(c, Tiles.C_BARREL)
	_put(Vector2i(31, 3), Tiles.C_ALTAR)
	_put(Vector2i(32, 3), Tiles.C_ALTAR)
	for c in [Vector2i(23, 4), Vector2i(41, 4), Vector2i(23, 9), Vector2i(41, 9)]:
		_put(c, Tiles.C_PILLAR)
	# wall variety on walls that face a floor
	for x in W:
		for y in range(0, H - 1):
			var c := Vector2i(x, y)
			if _at(c) == Tiles.C_WALL and _at(c + Vector2i.DOWN) in [Tiles.C_FLOOR, Tiles.C_FLOOR2, Tiles.C_RUBBLE]:
				var roll := _r.randf()
				if roll < 0.10:
					_put(c, Tiles.C_WALL_BANNER)
				elif roll < 0.17:
					_put(c, Tiles.C_WALL_SKULL)
				elif roll < 0.25:
					_put(c, Tiles.C_WALL_GRATE)


func _floor_rect(r: Rect2i) -> void:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var roll := _r.randf()
			_put(Vector2i(x, y), Tiles.C_RUBBLE if roll < 0.05 else (Tiles.C_FLOOR2 if roll < 0.12 else Tiles.C_FLOOR))


# ---------------------------------------------------------------- Frostpeak Ruins

func _gen_frost() -> void:
	for x in W:
		for y in H:
			var roll := _r.randf()
			var t := Tiles.S_SNOW
			if roll < 0.10:
				t = [Tiles.S_PINE, Tiles.S_PINE2, Tiles.S_PINE, Tiles.S_DEAD][_r.randi() % 4]
			elif roll < 0.125:
				t = Tiles.S_ROCK
			elif roll < 0.24:
				t = Tiles.S_SNOW2
			_put(Vector2i(x, y), t)
	_ellipse(Vector2(28, 9), Vector2(9, 4.5), [Tiles.S_ICE])          # frozen lake (walkable)
	_ellipse(Vector2(20, 31), Vector2(6, 3.5), [Tiles.S_ICE])
	# ruined fortress in the east = Yeti King's arena
	var fort := Rect2i(44, 11, 17, 19)
	for x in range(fort.position.x, fort.end.x):
		for y in range(fort.position.y, fort.end.y):
			var edge := x == fort.position.x or y == fort.position.y or x == fort.end.x - 1 or y == fort.end.y - 1
			var c := Vector2i(x, y)
			if edge:
				_put(c, Tiles.S_WALL if _r.randf() < 0.85 else Tiles.S_FLOOR)  # crumbling walls
			else:
				_put(c, Tiles.S_FLOOR if _r.randf() < 0.93 else Tiles.S_SNOW2)
	for y in range(18, 23):
		_put(Vector2i(fort.position.x, y), Tiles.S_FLOOR)                 # main gate (west)
	for c in [Vector2i(48, 14), Vector2i(56, 14), Vector2i(48, 26), Vector2i(56, 26)]:
		_put(c, Tiles.S_WALL)
	# small watchtower ruins
	_ruin(Rect2i(30, 25, 7, 6), Vector2i(32, 25), Tiles.S_WALL, Tiles.S_FLOOR)
	_ruin(Rect2i(10, 4, 7, 6), Vector2i(12, 9), Tiles.S_WALL, Tiles.S_FLOOR)
	for c in [Vector2i(14, 15), Vector2i(38, 21), Vector2i(22, 22)]:
		_put(c, Tiles.S_SNOWMAN)
	# keep a clear trail from the west gate into the fortress
	_carve_path([Vector2i(0, 20), Vector2i(14, 20), Vector2i(30, 19), Vector2i(44, 19)], Tiles.S_SNOW3, 3)


# ---------------------------------------------------------------- Dungeon instances

## Rooms + corridors (or caves) from the instance's layout, tiles from its theme.
func _gen_dungeon(d: Dictionary) -> void:
	var th: Dictionary = Dungeons.THEMES[d["theme"]]
	var floors: Array = []
	for n in th["floor"]:
		floors.append(Dungeons.tile(n))
	var walls: Array = []
	for n in th["wall"]:
		walls.append(Dungeons.tile(n))
	for x in W:
		for y in H:
			_put(Vector2i(x, y), walls[_r.randi() % walls.size()])
	var rooms: Array = d["rooms"]
	var order: Array = d["order"]
	var cave: bool = d["cave"]
	for r in rooms:
		var rect: Rect2i = r
		if cave:
			var c := Vector2(rect.get_center())
			var rad := Vector2(rect.size) / 2.0
			for x in range(rect.position.x - 1, rect.end.x + 1):
				for y in range(rect.position.y - 1, rect.end.y + 1):
					var q := Vector2((x - c.x) / rad.x, (y - c.y) / rad.y)
					if q.length_squared() <= 1.0 + _r.randf_range(-0.12, 0.12):
						_put(Vector2i(x, y), floors[_r.randi() % floors.size()])
		else:
			for x in range(rect.position.x, rect.end.x):
				for y in range(rect.position.y, rect.end.y):
					_put(Vector2i(x, y), floors[_r.randi() % floors.size()])
	var f0: Vector2i = floors[0]
	var lr := RandomNumberGenerator.new()
	lr.seed = int(d["loop_seed"])
	var links: Array = []
	for i in order.size() - 1:
		links.append([order[i], order[i + 1]])
	for i in order.size() - 2:   # a couple of shortcuts / loops
		if lr.randf() < 0.25:
			links.append([order[i], order[i + 2]])
	for l in links:
		var a: Vector2i = (rooms[l[0]] as Rect2i).get_center()
		var b: Vector2i = (rooms[l[1]] as Rect2i).get_center()
		var corner := Vector2i(b.x, a.y) if lr.randf() < 0.5 else Vector2i(a.x, b.y)
		var wd := 3 if cave else 2
		_carve(a, corner, f0, wd)
		_carve(corner, b, f0, wd)
	# decorations: only on open cells whose 8 neighbours are all open, never next to each other
	var deco: Array = []
	for n in th["decor"]:
		deco.append(Dungeons.tile(n))
	var start: Rect2i = rooms[order[0]]
	var boss_c: Vector2i = d["boss_cell"]
	for r in rooms:
		var rect: Rect2i = r
		if rect == start:
			continue
		for k in 3:
			var c := Vector2i(_r.randi_range(rect.position.x + 1, rect.end.x - 2), _r.randi_range(rect.position.y + 1, rect.end.y - 2))
			if Vector2(c).distance_to(Vector2(boss_c)) < 3.0:
				continue
			var ok := true
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if _at(c + Vector2i(dx, dy)) in Tiles.SOLID:
						ok = false
			if ok:
				_put(c, deco[_r.randi() % deco.size()])
	# hard border
	for x in W:
		for y in H:
			if x < 1 or y < 1 or x >= W - 1 or y >= H - 1:
				_put(Vector2i(x, y), walls[0])
