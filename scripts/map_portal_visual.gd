extends Node2D
## A map (dungeon) portal in town / a hideout: a visible gate, its labels ABOVE it and the entry
## area exactly on the drawn gate (MapPortalVisual.trigger_rect, also used by the server).
## Art (swappable): SPRITE_PATH is a horizontal strip of square frames (any count), drawn scaled
## to SIZE with nearest filtering - now SpritePilot's CC0 "Portal" (16 px, 8 frames, 10 fps). When
## someone steps through, TELEPORT_PATH (SpritePilot "Teleport", 12 frames, 15 fps, one-shot)
## plays on the gate. Missing art -> a procedural placeholder.

const SIZE := Vector2(48, 48)            # the drawn gate = the entry area (px, centred on the portal pos; 16 px art x3)
const SPRITE_PATH := "res://assets/fx/portal/portal-16px_strip8.png"
const FPS := 10.0
const TELEPORT_PATH := "res://assets/fx/portal/teleport-16px_strip12.png"
const TELEPORT_FPS := 15.0

var text := ""
var owner_name := ""
var _t := 0.0
var _label: Label
var _hint: Label
var _tex: Texture2D
var _frames := 1
var _tp_tex: Texture2D
var _tp_t := -1.0           # >= 0: teleport beam playing (seconds since start)
var _inside := {}           # instance ids of players standing on the gate last frame


static func trigger_rect(pos: Vector2) -> Rect2:
	return Rect2(pos - SIZE / 2.0, SIZE)


## Imported texture, or the raw PNG (a clone whose .godot cache predates the file).
static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
	return ImageTexture.create_from_image(img) if img else null


func _ready() -> void:
	z_index = 2    # above the ground tiles and decorations (the old gate sat at z -1, under the map)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex = _load_tex(SPRITE_PATH)
	if _tex and _tex.get_height() > 0:
		_frames = maxi(1, _tex.get_width() / _tex.get_height())
	_tp_tex = _load_tex(TELEPORT_PATH)
	_label = Label.new()
	_label.text = text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.size = Vector2(200, 34)
	_label.z_index = 30
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_label.resized.connect(_place_label)
	_place_label()
	_hint = Label.new()
	_hint.text = "Step in to enter"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(120, 16)
	_hint.position = Vector2(-60, SIZE.y / 2.0 + 2.0)
	_hint.z_index = 30
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(_hint)


## Label bottom edge 2 px above the gate, whatever height the font gives it.
func _place_label() -> void:
	_label.position = Vector2(-_label.size.x / 2.0, -SIZE.y / 2.0 - 2.0 - _label.size.y)


## (client) the gate, the entry area and the label, in zone coordinates - for tests.
func layout_info() -> Dictionary:
	var lr := Rect2(position + _label.position, _label.size)
	return {"gate": trigger_rect(position), "label_bottom": lr.end.y, "z": z_index, "art": "sprite" if _tex else "placeholder"}


func _process(delta: float) -> void:
	_t += delta
	var main := get_tree().root.get_node_or_null("Main")
	var me: Node = main._local_player() if main and main.has_method("_local_player") else null
	_hint.visible = me != null and me.get_parent() != null and me.zone == get_parent().get_parent() \
		and me.position.distance_to(position) < 90.0
	# someone who stood on the gate is gone this frame -> they went through: play the beam
	var now := {}
	var zone := get_parent().get_parent()
	if zone and "players_root" in zone and zone.players_root:
		for p in zone.players_root.get_children():
			if not p.is_queued_for_deletion() and trigger_rect(position).grow(24.0).has_point(p.position):   # (client positions lag the server a little)
				now[p.get_instance_id()] = true
	for id in _inside:
		if not now.has(id):
			var o = instance_from_id(id)
			if o == null or not is_instance_valid(o) or o.is_queued_for_deletion():
				_tp_t = 0.0
				var m := get_tree().root.get_node_or_null("Main")
				if m and m.bot_mode and not m.is_dedicated:
					m._log("portal fx: teleport beam on %s's gate at %s (art %s)" % [owner_name, position, "sprite" if _tp_tex else "none"])
	_inside = now
	if _tp_t >= 0.0:
		_tp_t += delta
		if _tp_t * TELEPORT_FPS >= 12.0:
			_tp_t = -1.0
	queue_redraw()


func _draw() -> void:
	var r := Rect2(-SIZE / 2.0, SIZE)
	if _tex:
		var fw := _tex.get_height()
		var f := int(_t * FPS) % _frames
		draw_texture_rect_region(_tex, r, Rect2(f * fw, 0, fw, fw))
		if _tp_t >= 0.0 and _tp_tex:
			var th := _tp_tex.get_height()
			var tf := mini(int(_tp_t * TELEPORT_FPS), _tp_tex.get_width() / th - 1)
			draw_texture_rect_region(_tp_tex, Rect2(-SIZE.x / 2.0, -SIZE.y, SIZE.x, SIZE.y * 1.5), Rect2(tf * th, 0, th, th))
		return
	# placeholder: stone frame + glowing purple oval with a turning swirl
	var c := Vector2.ZERO
	var rx := SIZE.x / 2.0
	var ry := SIZE.y / 2.0
	draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	draw_circle(Vector2.ZERO, rx, Color(0.25, 0.22, 0.3))                              # stone ring
	draw_circle(Vector2.ZERO, rx - 3.0, Color(0.45, 0.2, 0.85, 0.9))                   # portal body
	draw_circle(Vector2.ZERO, (rx - 3.0) * (0.6 + 0.08 * sin(_t * 3.0)), Color(0.7, 0.5, 1.0, 0.9))
	draw_circle(Vector2.ZERO, (rx - 3.0) * 0.25, Color(0.95, 0.9, 1.0, 0.95))
	for i in 3:
		var a0 := _t * 2.5 + i * TAU / 3.0
		draw_arc(Vector2.ZERO, (rx - 6.0) * 0.8, a0, a0 + 1.6, 10, Color(0.95, 0.85, 1.0, 0.85), 2.0)
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(-rx - 2.0, ry - 4.0, SIZE.x + 4.0, 6.0), Color(0.3, 0.27, 0.33))      # threshold step
