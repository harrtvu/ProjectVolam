extends PanelContainer
## Character sheet (C): class, element, stats, skills and the element cycle diagram.

const WheelScript := preload("res://scripts/element_wheel.gd")

var player: Node
var _head: Label
var _sub: Label
var _icon: TextureRect
var _stats: Label
var _vs: Label
var _wheel: Control
var _scroll: ScrollContainer
var _left: VBoxContainer


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	sb.border_color = Color(1, 0.85, 0.4, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	add_child(hb)
	_scroll = ScrollContainer.new()   # the text column scrolls when the window is too short for it
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(_scroll)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	_scroll.add_child(left)
	_left = left
	var t := Label.new()
	t.text = "Character  (C to close)"
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	left.add_child(t)
	var top := HBoxContainer.new()
	left.add_child(top)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(48, 48)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.add_child(_icon)
	var names := VBoxContainer.new()
	top.add_child(names)
	_head = Label.new()
	_head.add_theme_font_size_override("font_size", 18)
	names.add_child(_head)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 12)
	names.add_child(_sub)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.custom_minimum_size = Vector2(270, 0)
	left.add_child(_stats)
	_vs = Label.new()
	_vs.add_theme_font_size_override("font_size", 12)
	_vs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vs.custom_minimum_size = Vector2(250, 0)
	left.add_child(_vs)
	var right := VBoxContainer.new()
	hb.add_child(right)
	var wt := Label.new()
	wt.text = "Ngũ Hành - the five elements"
	wt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wt.add_theme_font_size_override("font_size", 13)
	right.add_child(wt)
	_wheel = WheelScript.new()
	right.add_child(_wheel)
	var legend := Label.new()
	legend.text = "green arrows: generates (sinh) - +20% healing\nred dashes: overcomes (khắc) - +25% dmg / -20% back"
	legend.add_theme_font_size_override("font_size", 11)
	legend.modulate = Color(1, 1, 1, 0.75)
	right.add_child(legend)


func set_player(p: Node) -> void:
	player = p


func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(player):
		return
	var d := Classes.info(player.class_id)
	var e: String = player.element
	var col := Classes.color(e)
	_icon.texture = Classes.element_icon(e, true)
	_head.text = "%s - %s" % [player.display_name, d["name"]]
	_head.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.3))
	_sub.text = "%s  |  %s" % [Classes.element_name(e), d["role"]]
	_sub.add_theme_color_override("font_color", col)
	var lines := [
		"Level %d   XP %d / %d" % [player.level, player.xp, player.xp_next],
		"HP %d / %d     Mana %d / %d" % [player.hp, player.max_hp, player.mp, player.max_mp],
		"Attack %d     Defense %d" % [player.attack, player.defense],
		"Crit %.1f%% (x%.2f)     Speed %d" % [player.crit * 100.0, player.crit_mult(), roundi(player.move_speed)],
		"Resistances (cap %d%%):" % roundi(Gear.RES_CAP),
		_res_text(),
		"Weapon: %s     Gear pieces: %d/10" % [Gear.display_name(player.equipment.get("weapon", {})) if not player.equipment.get("weapon", {}).is_empty() else "-", _worn()],
		"",
		"Skills:",
	]
	for i in 4:
		var sid := Classes.skill_id(player.class_id, i)
		var sk: Dictionary = player.skill_def(sid)
		var lock: String = "" if player.level >= Classes.UNLOCK_LEVELS[i] else "  (unlocks Lv %d)" % Classes.UNLOCK_LEVELS[i]
		var base: Dictionary = Classes.SKILLS[sid]
		var extra := ""
		if sk.has("mult") and absf(float(sk["mult"]) - float(base["mult"])) > 0.001:
			extra += "  dmg %d%%" % roundi(float(sk["mult"]) * 100.0)
		if sk.has("radius") and absf(float(sk["radius"]) - float(base["radius"])) > 0.5:
			extra += "  area %d" % roundi(float(sk["radius"]))
		lines.append("[%d] %s - %d mana, %.1fs%s%s" % [i + 1, sk["name"], sk["cost"], sk["cd"], extra, lock])
	var total := Talents.points_total(player.level)
	var spent := Talents.points_spent(player.talents)
	lines.append("")
	lines.append("Passive web (T): %d / %d points spent" % [spent, total])
	var tnames: Array = []
	for id in player.talents:
		var n := Talents.node(str(id))
		if not n.is_empty() and n["type"] != "small":
			tnames.append(("[K] " if n["type"] == "keystone" else "") + str(n["name"]))
	if not tnames.is_empty():
		lines.append("Notables: " + ", ".join(tnames))
	var bon := Stats.describe(player.tmods)
	if not bon.is_empty():
		lines.append("Bonuses: " + ", ".join(bon))
	_stats.text = "\n".join(lines)
	var strong: String = Classes.OVERCOMES[e]
	var weak := ""
	for k in Classes.OVERCOMES:
		if Classes.OVERCOMES[k] == e:
			weak = k
	_vs.text = "Strong vs %s monsters (+25%% damage dealt, -20%% taken).\nCareful with %s monsters (-20%% damage dealt, +25%% taken)." % [
		Classes.element_name(strong), Classes.element_name(weak)]
	_wheel.highlight = e
	_wheel.queue_redraw()
	# fit the screen: the column is as tall as its text, but never past the bottom of the window
	var need := _left.get_combined_minimum_size()
	var avail := get_viewport_rect().size.y - global_position.y - 34.0
	_scroll.custom_minimum_size = Vector2(need.x + 10.0, clampf(need.y, 120.0, maxf(120.0, avail)))
	reset_size()


func _res_text() -> String:
	var parts: Array = []
	for e in Gear.ELEMENTS:
		parts.append("%s\u00a0%d%%" % [Classes.ELEMENT_INFO[e]["name"], roundi(player.resistance(e))])
	return "   ".join(parts.slice(0, 3)) + "\n" + "   ".join(parts.slice(3))   # no-break space: "Wood" never splits from "0%"


func _worn() -> int:
	var n := 0
	for sl in player.equipment:
		if not player.equipment[sl].is_empty():
			n += 1
	return n
