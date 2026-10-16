extends PanelContainer
## Passive web panel (T): the whole shared web, pannable (drag) and zoomable (wheel).
## Left-click a highlighted node to allocate it, right-click an allocated node twice to
## refund it for gold, "Reset web" (click twice) refunds everything for gold.

var player: Node
var _title: Label
var _points: Label
var _reset: Button
var _view: WebView
var _confirm_until := 0


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.96)
	sb.border_color = Color(1, 0.85, 0.4, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	vb.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_points = Label.new()
	_points.add_theme_font_size_override("font_size", 14)
	top.add_child(_points)
	_reset = Button.new()
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.pressed.connect(_on_reset)
	top.add_child(_reset)
	_view = WebView.new()
	_view.panel = self
	_view.custom_minimum_size = Vector2(900, 520)
	_view.clip_contents = true
	vb.add_child(_view)
	var hint := Label.new()
	hint.text = "Left-click a glowing node next to your allocation to spend a point.  Right-click an allocated node twice to refund it for gold.  Drag to pan, wheel to zoom, Space/Home to recentre.  T to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.65)
	vb.add_child(hint)


func set_player(p: Node) -> void:
	if p != player:
		player = p
		_view.recentre()


func _on_reset() -> void:
	if not is_instance_valid(player):
		return
	if Time.get_ticks_msec() > _confirm_until:
		_confirm_until = Time.get_ticks_msec() + 3000
		return
	_confirm_until = 0
	player.request_respec()


func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(player):
		return
	var tl: Dictionary = player.talents
	var total := Talents.points_total(player.level)
	var spent := Talents.points_spent(tl)
	_title.text = "Passive Web - %s" % Classes.info(player.class_id)["name"]
	_title.add_theme_color_override("font_color", Classes.color(Classes.element_of(player.class_id)))
	_points.text = "Points: %d available  (%d / %d spent)   Refund: %d gold/node   Gold: %d" % [total - spent, spent, total,
		Talents.refund_cost(player.level), player.gold]
	var cost := Talents.respec_cost(player.level)
	if Time.get_ticks_msec() < _confirm_until:
		_reset.text = "Click again: reset for %d gold" % cost
	else:
		_reset.text = "Reset web (%d gold)" % cost
	_reset.disabled = spent == 0 or player.gold < cost
	# fit the window (the web view shrinks on small screens) and stay centred
	var vs := get_viewport_rect().size
	_view.custom_minimum_size = Vector2(minf(900.0, vs.x - 60.0), minf(520.0, vs.y - 130.0))
	size = Vector2.ZERO
	position = Vector2(roundf((vs.x - size.x) / 2.0), 36.0)
	_view.queue_redraw()


class WebView extends Control:
	var panel: Node
	var center := Vector2.ZERO
	var zoom := 0.8
	var hover := ""
	var _drag := false
	var _drag_moved := 0.0
	var _refund_id := ""
	var _refund_until := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func recentre() -> void:
		var p = panel.player if panel else null
		if is_instance_valid(p):
			# halfway between the class start and the web centre: shows both clusters and the hub
			center = Talents.node(Talents.start_of(p.class_id))["pos"] * 0.75
		zoom = 0.8

	func to_screen(v: Vector2) -> Vector2:
		return size / 2.0 + (v - center) * zoom

	func to_web(s: Vector2) -> Vector2:
		return center + (s - size / 2.0) / zoom

	func _radius(n: Dictionary) -> float:
		match n["type"]:
			"small": return 6.0
			"notable": return 11.0
			"keystone": return 15.0
		return 17.0

	func _node_at(s: Vector2) -> String:
		var best := ""
		var best_d := 99999.0
		for id in Talents.all_nodes():
			var n: Dictionary = Talents.node(id)
			var d := to_screen(n["pos"]).distance_to(s)
			if d <= maxf(8.0, _radius(n) * zoom + 4.0) and d < best_d:
				best_d = d
				best = id
		return best

	func _gui_input(event: InputEvent) -> void:
		var p = panel.player
		if not is_instance_valid(p):
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var before := to_web(mb.position)
					zoom = clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.35, 2.5)
					center += before - to_web(mb.position)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_drag = true
					_drag_moved = 0.0
				else:
					_drag = false
					if _drag_moved < 6.0:
						var id := _node_at(mb.position)
						if id != "" and not Talents.is_allocated(p.class_id, p.talents, id):
							p.request_talent(id)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var id := _node_at(mb.position)
				if id != "" and p.talents.has(id):
					if _refund_id == id and Time.get_ticks_msec() < _refund_until:
						p.request_refund(id)
						_refund_id = ""
					else:
						_refund_id = id
						_refund_until = Time.get_ticks_msec() + 3000
				accept_event()
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _drag:
				center -= mm.relative / zoom
				_drag_moved += mm.relative.length()
			hover = _node_at(mm.position)
			accept_event()
		elif event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_HOME):
			recentre()
			accept_event()

	func _col_for(n: Dictionary) -> Color:
		if n["cls"] != "":
			return Classes.color(Classes.element_of(n["cls"]))
		return Color(0.95, 0.82, 0.45)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.06, 1.0))
		var p = panel.player if panel else null
		if not is_instance_valid(p):
			return
		var cls: String = p.class_id
		var tl: Dictionary = p.talents
		var points_left := Talents.points_total(p.level) - Talents.points_spent(tl)
		var font := get_theme_default_font()
		var nodes := Talents.all_nodes()
		# faint pentagon of the five elements (generating cycle) behind the web
		for i in 5:
			var a: Vector2 = Talents.node(Talents.start_of(Talents.RING_ORDER[i]))["pos"]
			var b: Vector2 = Talents.node(Talents.start_of(Talents.RING_ORDER[(i + 1) % 5]))["pos"]
			draw_line(to_screen(a * 1.12), to_screen(b * 1.12), Color(1, 1, 1, 0.05), 2.0)
		# edges
		for id in nodes:
			var n: Dictionary = nodes[id]
			var a_on := Talents.is_allocated(cls, tl, id)
			for l in n["links"]:
				if str(l) < str(id):
					continue
				var b_on := Talents.is_allocated(cls, tl, l)
				var c := Color(0.35, 0.35, 0.4, 0.55)
				var w := 2.0
				if a_on and b_on:
					c = Color(1.0, 0.85, 0.4, 0.95)
					w = 3.5
				elif a_on or b_on:
					c = Color(0.75, 0.75, 0.85, 0.75)
				draw_line(to_screen(n["pos"]), to_screen(nodes[l]["pos"]), c, w * clampf(zoom, 0.6, 1.4))
		# nodes
		for id in nodes:
			var n: Dictionary = nodes[id]
			var sp := to_screen(n["pos"])
			var r := _radius(n) * zoom
			if sp.x < -40 or sp.y < -40 or sp.x > size.x + 40 or sp.y > size.y + 40:
				continue
			var on := Talents.is_allocated(cls, tl, id)
			var can := not on and points_left > 0 and Talents.is_adjacent(cls, tl, id)
			var col := _col_for(n)
			var fill := col if on else Color(0.12, 0.12, 0.16)
			if n["type"] == "keystone":
				var pts := PackedVector2Array()
				for k in 8:
					pts.append(sp + Vector2.from_angle(TAU * k / 8.0 + PI / 8.0) * r)
				draw_colored_polygon(pts, fill)
				pts.append(pts[0])
				draw_polyline(pts, Color(1, 0.9, 0.5) if (on or can) else Color(0.5, 0.5, 0.55), 2.0)
			else:
				draw_circle(sp, r, fill)
				draw_arc(sp, r, 0, TAU, 20, col.lightened(0.3) if (on or can) else Color(0.45, 0.45, 0.5), 2.0 if n["type"] != "small" else 1.5)
			if n["type"] == "start":
				var tex := Classes.element_icon(Classes.element_of(n["cls"]))
				var s := r * 1.3
				draw_texture_rect(tex, Rect2(sp - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, 1.0 if on else 0.6))
			if can:
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
				draw_arc(sp, r + 3.0, 0, TAU, 24, Color(0.6, 1.0, 0.6, 0.4 + 0.5 * pulse), 2.0)
			if id == _refund_id and Time.get_ticks_msec() < _refund_until:
				draw_arc(sp, r + 4.0, 0, TAU, 24, Color(1, 0.3, 0.3), 2.5)
			var show_name: bool = n["type"] == "start" or n["type"] == "keystone" or (n["type"] == "notable" and zoom >= 1.05)
			if show_name:
				var fs := 12 if n["type"] != "notable" else 11
				var tw := font.get_string_size(n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, sp + Vector2(-tw / 2.0, r + 13.0), n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1, 1, 1, 0.9) if on or can else Color(0.8, 0.8, 0.85, 0.7))
		_draw_tooltip(font, cls, tl, p)

	func _draw_tooltip(font: Font, cls: String, tl: Dictionary, p: Node) -> void:
		if hover == "":
			return
		var n := Talents.node(hover)
		var lines: Array = []
		var kind: String = {"small": "Passive", "notable": "Notable", "keystone": "KEYSTONE", "start": "Class start"}[n["type"]]
		lines.append([str(n["name"]), 15, _col_for(n)])
		lines.append([kind + ("  -  " + Classes.ELEMENT_INFO[n["cls"]]["name"] + " region" if n["cls"] != "" else ""), 11, Color(0.7, 0.7, 0.75)])
		for chunk in str(n["desc"]).split(", "):
			lines.append([chunk, 13, Color(0.9, 0.95, 1.0)])
		var state := ""
		var sc := Color(0.6, 1.0, 0.6)
		if hover == Talents.start_of(cls):
			state = "Your class start (free)"
		elif tl.has(hover):
			var why := Talents.can_refund(cls, tl, hover)
			state = ("Right-click twice to refund (%d gold)" % Talents.refund_cost(p.level)) if why == "" else "Can't refund: " + why
			sc = Color(1.0, 0.85, 0.5) if why == "" else Color(1, 0.5, 0.45)
		else:
			var why := Talents.can_learn(cls, p.level, tl, hover)
			state = "Click to allocate (1 point)" if why == "" else why
			if why != "":
				sc = Color(1, 0.5, 0.45)
		lines.append([state, 12, sc])
		var w := 0.0
		var h := 8.0
		for l in lines:
			w = maxf(w, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1]).x)
			h += l[1] + 5
		var pos := to_screen(n["pos"]) + Vector2(18, -h / 2.0)
		if pos.x + w + 16 > size.x:
			pos.x = to_screen(n["pos"]).x - w - 34
		pos.y = clampf(pos.y, 4, size.y - h - 4)
		draw_rect(Rect2(pos, Vector2(w + 16, h)), Color(0.02, 0.02, 0.04, 0.95))
		draw_rect(Rect2(pos, Vector2(w + 16, h)), Color(1, 0.85, 0.4, 0.6), false, 1.5)
		var y := pos.y + 4
		for l in lines:
			y += l[1] + 2
			draw_string(font, Vector2(pos.x + 8, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1], l[2])
			y += 3
