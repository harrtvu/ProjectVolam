extends PanelContainer
## Martial Forms panel (F): pick a Vo Lam combo route and socket PoE-style support links.

var player: Node
var _title: Label
var _form_box: VBoxContainer
var _support_box: VBoxContainer
var _combo: Label
var _status: Label
var _form_btns: Array = []
var _support_rows: Array = []
var _built_for := ""   # form_id|supports|level signature — rebuild only when it changes


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.1, 0.94)
	sb.border_color = Color(0.85, 0.65, 0.3, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(520, 420)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_title = Label.new()
	_title.text = "Martial Forms  (F to close)"
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_title.add_theme_font_size_override("font_size", 16)
	root.add_child(_title)
	var blurb := Label.new()
	blurb.text = "Vo Lam combo routes + Path of Exile support links.\nCast skills in the Form's order for a Finisher. Socket supports to reshape the build."
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.modulate = Color(1, 1, 1, 0.75)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(480, 0)
	root.add_child(blurb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	root.add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var lf := Label.new()
	lf.text = "Forms (chiêu thức)"
	lf.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	left.add_child(lf)
	_form_box = VBoxContainer.new()
	_form_box.add_theme_constant_override("separation", 6)
	left.add_child(_form_box)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var ls := Label.new()
	ls.text = "Support Links (PoE)"
	ls.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	right.add_child(ls)
	_support_box = VBoxContainer.new()
	_support_box.add_theme_constant_override("separation", 6)
	right.add_child(_support_box)
	_combo = Label.new()
	_combo.add_theme_font_size_override("font_size", 12)
	_combo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_combo.custom_minimum_size = Vector2(480, 0)
	root.add_child(_combo)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.modulate = Color(0.7, 0.9, 0.7)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(480, 0)
	root.add_child(_status)


func set_player(p: Node) -> void:
	player = p
	if not is_instance_valid(player):
		return
	var sig := "%s|%s|%d" % [player.form_id, ",".join(player.form_supports), player.level]
	if sig != _built_for:
		_built_for = sig
		_rebuild()


func _rebuild() -> void:
	for c in _form_box.get_children():
		c.queue_free()
	for c in _support_box.get_children():
		c.queue_free()
	_form_btns.clear()
	_support_rows.clear()
	if not is_instance_valid(player):
		return
	var cls: String = player.class_id
	for f in Forms.for_class(cls):
		var locked: bool = player.level < int(f["unlock"])
		var active: bool = str(f["id"]) == str(player.form_id)
		var b := Button.new()
		b.text = "%s%s  (%s)%s" % ["▶ " if active else "", f["name"], f["viet"], "  [Lv %d]" % int(f["unlock"]) if locked else ""]
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = locked
		b.tooltip_text = "%s\n%s\nCombo: %s\nFinisher: +%d%% skill damage for %.0fs\nSupport sockets: %d" % [
			f["desc"], f["playstyle"], Forms.combo_label(cls, f["id"]), int(f["finisher_dmg"]), Forms.FINISHER_DURATION, int(f["links"])]
		var fid := str(f["id"])
		b.pressed.connect(func(): _pick_form(fid))
		_form_box.add_child(b)
		_form_btns.append(b)
	var factive := Forms.form(cls, player.form_id)
	var links := mini(int(factive.get("links", 1)), Forms.MAX_LINKS) if not factive.is_empty() else 0
	for i in links:
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = "Link %d" % (i + 1)
		lab.custom_minimum_size = Vector2(48, 0)
		row.add_child(lab)
		var opt := OptionButton.new()
		opt.focus_mode = Control.FOCUS_NONE
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt.add_item("(empty)", 0)
		opt.set_item_metadata(0, "")
		var cur := ""
		if i < player.form_supports.size():
			cur = str(player.form_supports[i])
		var idx := 0
		var n := 1
		for sid in Forms.support_ids():
			var sp: Dictionary = Forms.SUPPORTS[sid]
			var lock: bool = player.level < int(sp["min_level"])
			var label: String = "%s [%s]" % [sp["name"], sp["viet"]]
			if lock:
				label += " (Lv %d)" % int(sp["min_level"])
			opt.add_item(label, n)
			opt.set_item_metadata(n, sid)
			opt.set_item_disabled(n, lock)
			opt.set_item_tooltip(n, sp["desc"])
			if sid == cur:
				idx = n
			n += 1
		opt.select(idx)
		var slot := i
		opt.item_selected.connect(func(ii): _pick_support(slot, str(opt.get_item_metadata(ii))))
		row.add_child(opt)
		_support_box.add_child(row)
		_support_rows.append(opt)
	if factive.is_empty():
		_combo.text = "No Form selected."
	else:
		_combo.text = "Active: %s (%s)\nCombo: %s\nFinisher: +%d%% skill damage for %.0fs after the full route." % [
			factive["name"], factive["viet"], Forms.combo_label(cls, player.form_id),
			int(factive["finisher_dmg"]), Forms.FINISHER_DURATION]
		var fin: String = ""
		if player.finisher_t > 0.0:
			fin = "  Finisher buff: +%d%% (%.1fs)" % [roundi(player.finisher_dmg), player.finisher_t]
		var steps: int = (factive["combo"] as Array).size() if not factive.is_empty() else 0
		_status.text = "Combo step %d / %d%s" % [player.combo_step, steps, fin]


func _pick_form(id: String) -> void:
	if is_instance_valid(player):
		_built_for = ""   # force rebuild when the server echoes the new Form
		player.request_form(id)
		_status.text = "Requesting Form %s..." % id


func _pick_support(slot: int, support_id: String) -> void:
	if is_instance_valid(player):
		_built_for = ""
		player.request_form_support(slot, support_id)
		_status.text = "Socketing link %d..." % (slot + 1)


func _process(_delta: float) -> void:
	if visible and is_instance_valid(player):
		# keep the combo / finisher line live without rebuilding the OptionButtons every frame
		var factive := Forms.form(player.class_id, player.form_id)
		var fin2: String = ""
		if player.finisher_t > 0.0:
			fin2 = "  Finisher buff: +%d%% (%.1fs)" % [roundi(player.finisher_dmg), player.finisher_t]
		var steps2: int = (factive["combo"] as Array).size() if not factive.is_empty() else 0
		_status.text = "Combo step %d / %d%s" % [player.combo_step, steps2, fin2]
