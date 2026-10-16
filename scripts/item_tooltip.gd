extends PanelContainer
## Floating item tooltip: rarity-coloured name, base stats, affixes (prefix/suffix + tier),
## requirements, and - for gear in the bag - a comparison against what is equipped in that slot.

var _text: RichTextLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	top_level = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.035, 0.05, 0.96)
	sb.border_color = Color(0.6, 0.5, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 12)
	_text.add_theme_font_size_override("bold_font_size", 14)
	add_child(_text)
	visible = false


static func _line(t: String, c: Color, bold := false) -> String:
	var s := "[color=#%s]%s[/color]" % [c.to_html(false), t.replace("[", "[lb]")]
	return ("[b]%s[/b]" % s) if bold else s


func show_gear(inst: Dictionary, player: Node, at: Vector2, compare_with: Dictionary = {}, compare_slot := "") -> void:
	var lines: Array = []
	var cls: String = player.class_id if player else ""
	var lvl: int = player.level if player else 99
	var tip := Gear.tooltip(inst, cls, lvl)
	for i in tip.size():
		lines.append(_line(str(tip[i][0]), tip[i][1], i == 0))
	if compare_slot != "":
		lines.append("")
		if compare_with.is_empty():
			lines.append(_line("Nothing equipped in %s - all of this is a gain" % Items.SLOT_NAMES.get(compare_slot, compare_slot), Color(0.5, 1, 0.5)))
		else:
			lines.append(_line("Compared to equipped: %s" % Gear.display_name(compare_with), Gear.RARITY_COLOR[str(compare_with.get("rarity", "normal"))]))
			for c in Gear.compare(inst, compare_with):
				lines.append(_line("   " + str(c[0]), c[1]))
	_show("\n".join(lines), at)


## A market listing: the item's tooltip + price / seller.
func show_listing(l: Dictionary, player: Node, at: Vector2) -> void:
	var tip := Market.tooltip(l, player.class_id if player else "", player.level if player else 99)
	var lines: Array = []
	for i in tip.size():
		lines.append(_line(str(tip[i][0]), tip[i][1], i == 0))
	_show("\n".join(lines), at)


func show_stack(id: String, n: int, at: Vector2) -> void:
	var info := Items.info(id)
	var lines: Array = [_line("%s  x%d" % [info["name"], n], Color(0.75, 0.95, 1.0) if Items.type_of(id) == "orb" else Color.WHITE, true)]
	lines.append(_line(str(info.get("desc", "")), Color(0.8, 0.8, 0.8)))
	if Items.type_of(id) == "orb":
		lines.append(_line("Right-click, then click an item to apply" + (" (at the blacksmith)" if id == "enhance_stone" else ""), Color(0.6, 0.6, 0.65)))
	elif Items.type_of(id) == "consumable":
		lines.append(_line("Click to drink (Q = quick potion)", Color(0.6, 0.6, 0.65)))
	_show("\n".join(lines), at)


func _show(bb: String, at: Vector2) -> void:
	_text.text = bb
	visible = true
	reset_size()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	reset_size()
	var vp := get_viewport_rect().size
	var p := at + Vector2(18, 10)
	if p.x + size.x > vp.x - 4:
		p.x = at.x - size.x - 12
	if p.y + size.y > vp.y - 4:
		p.y = vp.y - size.y - 4
	global_position = Vector2(maxf(p.x, 4.0), maxf(p.y, 4.0))


func hide_tip() -> void:
	visible = false
