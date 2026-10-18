extends Control
## Minimap of the current overworld zone (top-right of the HUD) and, with N, the full zone map.
## The terrain is a 1-pixel-per-tile image of the ZoneMap (rebuilt when the zone changes);
## markers: you (white), other players (cyan), zone portals (purple), town NPCs (yellow),
## monster camps (orange), elite circles (gold), the boss lair (red) and monsters you can see (red dots).

var main: Node = null
var big := false           # N: full zone map in the middle of the screen
var _zone_id := ""
var _tex: ImageTexture
var _map_size := Vector2i(1, 1)
const SMALL := Vector2(220, 141)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle_big() -> void:
	big = not big
	_layout()


func _layout() -> void:
	var vp := get_viewport_rect().size
	if big:
		var s := minf((vp.x - 120.0) / _map_size.x, (vp.y - 120.0) / _map_size.y)
		size = Vector2(_map_size) * s
		position = (vp - size) / 2.0
	else:
		size = SMALL
		position = Vector2(vp.x - SMALL.x - 10.0, 112.0)


func _process(_delta: float) -> void:
	var me: Node = main._local_player() if main else null
	visible = me != null and me.zone != null and Zones.DB.has(me.zone.zone_id) and main.hud.visible
	if not visible:
		return
	if me.zone.zone_id != _zone_id:
		_zone_id = me.zone.zone_id
		_map_size = Vector2i(me.zone.map.w, me.zone.map.h)
		_tex = ImageTexture.create_from_image(me.zone.map.overview_image())
	_layout()
	queue_redraw()


func _draw() -> void:
	var me: Node = main._local_player() if main else null
	if me == null or me.zone == null or _tex == null:
		return
	var z: Node = me.zone
	var k := size.x / _map_size.x   # screen px per tile
	var tp := func(local: Vector2) -> Vector2: return local / Zones.TILE * k
	draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color(0, 0, 0, 0.75))
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.92))
	var dot := 2.0 if not big else 3.5
	for st in z.map.sites:
		var c: Color = {"camp": Color(1.0, 0.55, 0.15), "elite": Color(1.0, 0.85, 0.2)}.get(st["kind"], Color(0, 0, 0, 0))
		if c.a > 0.0:
			draw_circle(tp.call(z.map.cell_pos(st["cell"])), dot + 0.5, c)
	if not z.info["boss"].is_empty():
		var bp: Vector2 = tp.call(z.map.cell_pos(z.info["boss"]["cell"]))
		draw_circle(bp, dot + 2.5, Color(0.9, 0.1, 0.1))
		draw_arc(bp, dot + 4.0, 0.0, TAU, 16, Color(1, 0.8, 0.3), 1.0)
	for m in z.monsters_root.get_children():
		if m.alive and not m.is_boss:
			draw_circle(tp.call(m.position), dot * 0.6, Color(1.0, 0.25, 0.2, 0.85))
	for p in z.info["portals"]:
		var r: Rect2i = p["rect"]
		draw_rect(Rect2(Vector2(r.position) * k, Vector2(r.size) * k).grow(1.5), Color(0.7, 0.4, 1.0))
	for key in ["map_device", "merchant", "vendor", "blacksmith", "hideout_master"]:
		if z.info.has(key):
			draw_circle(tp.call(z.map.cell_pos(z.info[key])), dot, Color(1.0, 0.95, 0.4))
	for p in z.players_root.get_children():
		if p != me:
			draw_circle(tp.call(p.position), dot + 0.5, Color(0.3, 0.9, 1.0))
	draw_circle(tp.call(me.position), dot + 1.5, Color.WHITE)
	draw_circle(tp.call(me.position), dot + 0.3, Color(0.1, 0.5, 1.0))
	var font := get_theme_default_font()
	draw_string(font, Vector2(4, 13 if not big else 18), z.info["name"] + ("" if big else "  (N: map)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11 if not big else 16, Color(1, 0.95, 0.8))
	if big:
		draw_string(font, Vector2(4, size.y - 8), "white: you   cyan: players   purple: portals   yellow: NPCs   orange: camps   gold: elites   red ring: boss lair   red dots: monsters", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9))
