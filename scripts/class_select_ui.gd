extends Control
## Full-screen class selection (shown once per character: new accounts, and
## old accounts saved before classes existed).

signal chosen(class_id: String)

var _title: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_right = -12
	root.offset_top = 10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_title = Label.new()
	_title.text = "Choose your element - Ngũ Hành"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	root.add_child(_title)
	var sub := Label.new()
	sub.text = "Metal > Wood > Earth > Water > Fire > Metal: each element deals +25% damage to the one it overcomes and 20% less to the one that overcomes it."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.75)
	root.add_child(sub)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	for cls in ["metal", "wood", "water", "fire", "earth"]:
		row.add_child(_card(cls))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.08, 0.94))


func set_subtitle(text: String) -> void:
	_title.text = text


func _card(cls: String) -> Control:
	var d := Classes.info(cls)
	var e: String = d["element"]
	var col := Classes.color(e)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(200, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 0.95)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(top)
	var icon := TextureRect.new()
	icon.texture = Classes.element_icon(e, true)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon)
	var spr := TextureRect.new()
	spr.texture = load("res://assets/classes/%s_0.png" % cls)
	spr.custom_minimum_size = Vector2(44, 44)
	spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(spr)
	vb.add_child(_lbl("%s" % d["name"], 17, col.lerp(Color.WHITE, 0.3), true))
	vb.add_child(_lbl(Classes.element_name(e), 13, col, true))
	vb.add_child(_lbl(str(d["role"]), 12, Color(1, 1, 1, 0.9), true))
	var desc := _lbl(str(d["desc"]), 11, Color(1, 1, 1, 0.7), false)
	desc.custom_minimum_size = Vector2(170, 0)
	vb.add_child(desc)
	# stat preview (level 1 and level 10)
	for st in [["HP", "hp", 130.0], ["Mana", "mp", 100.0], ["Attack", "atk", 15.0], ["Defense", "def", 8.0]]:
		vb.add_child(_stat_row(st[0], Classes.stat(cls, st[1], 1), Classes.stat(cls, st[1], 10), st[2], col))
	vb.add_child(_stat_row("Speed", float(d["speed"]), float(d["speed"]), 180.0, col))
	vb.add_child(_stat_row("Crit %", Classes.stat(cls, "crit", 1) * 100.0, Classes.stat(cls, "crit", 10) * 100.0, 25.0, col))
	vb.add_child(_lbl("Basic attack: " + ("melee" if d["basic"] == "melee" else "ranged bolt"), 11, Color(1, 1, 1, 0.75), false))
	vb.add_child(_lbl("Skills:", 12, Color(1, 0.9, 0.6), false))
	for i in 4:
		var sk: Dictionary = Classes.SKILLS[d["skills"][i]]
		var h := HBoxContainer.new()
		var ic := TextureRect.new()
		ic.texture = Classes.skill_icon(d["skills"][i])
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.add_child(ic)
		var l := _lbl("%d. %s (Lv %d)" % [i + 1, sk["name"], Classes.UNLOCK_LEVELS[i]], 11, Color(1, 1, 1, 0.85), false)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = str(sk["desc"])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(l)
		vb.add_child(h)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	var btn := Button.new()
	btn.text = "Become a %s" % d["name"]
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): chosen.emit(cls))
	vb.add_child(btn)
	return panel


func _lbl(t: String, fs: int, c: Color, center: bool) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _stat_row(n: String, v1: float, v10: float, max_v: float, col: Color) -> Control:
	var h := HBoxContainer.new()
	var l := _lbl(n, 11, Color(1, 1, 1, 0.8), false)
	l.custom_minimum_size = Vector2(52, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = max_v
	bar.value = v10
	bar.custom_minimum_size = Vector2(70, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	h.add_child(bar)
	var fmt := "%.0f" if v1 >= 10.0 or n == "Speed" else "%.1f"
	var v := _lbl((fmt + "→" + fmt) % [v1, v10] if v1 != v10 else fmt % v1, 11, Color(1, 1, 1, 0.8), false)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.custom_minimum_size = Vector2(56, 0)
	h.add_child(v)
	return h
