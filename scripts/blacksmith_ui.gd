extends PanelContainer
## Blacksmith panel (press E next to the anvil in Sunny Meadow). Put an item in the slot
## (click it in your bag / paper doll, or drag it here), then apply crafting orbs or
## enhancement stones, sell it, or move it to the shared stash. All rolls happen on the server.

const SlotScript := preload("res://scripts/item_slot.gd")

var player: Node = null
var inventory: Control = null
var tooltip: Control = null
var selected_uid := -1
var _slot: Control
var _info: RichTextLabel
var _orb_buttons := {}
var _sell_btn: Button
var _stash_btn: Button
var _stash_slots: Array = []
var _stash_label: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.06, 0.95)
	sb.border_color = Color(1.0, 0.6, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(430, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var title := Label.new()
	title.text = "Blacksmith  -  crafting, enhancement, vendor & stash   (E / Esc to close)"
	title.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
	title.add_theme_font_size_override("font_size", 13)
	vb.add_child(title)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	_slot = SlotScript.new()
	_slot.kind = "smith"
	_slot.placeholder = "click an item"
	_slot.custom_minimum_size = Vector2(64, 64)
	_slot.dropped.connect(_on_slot_drop)
	_slot.hovered.connect(_on_hover)
	hb.add_child(_slot)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.custom_minimum_size = Vector2(330, 60)
	_info.add_theme_font_size_override("normal_font_size", 11)
	_info.add_theme_font_size_override("bold_font_size", 13)
	hb.add_child(_info)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for orb in Items.ORBS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.icon = Items.icon(orb)
		b.expand_icon = false
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(205, 30)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_constant_override("icon_max_width", 22)
		b.tooltip_text = str(Items.info(orb)["desc"])
		b.pressed.connect(_apply.bind(orb))
		grid.add_child(b)
		_orb_buttons[orb] = b
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	_sell_btn = Button.new()
	_sell_btn.focus_mode = Control.FOCUS_NONE
	_sell_btn.pressed.connect(_on_sell)
	row.add_child(_sell_btn)
	_stash_btn = Button.new()
	_stash_btn.focus_mode = Control.FOCUS_NONE
	_stash_btn.text = "Put in stash"
	_stash_btn.pressed.connect(_on_stash_put)
	row.add_child(_stash_btn)
	_stash_label = Label.new()
	_stash_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(_stash_label)
	var sgrid := GridContainer.new()
	sgrid.columns = 14
	sgrid.add_theme_constant_override("h_separation", 2)
	sgrid.add_theme_constant_override("v_separation", 2)
	vb.add_child(sgrid)
	for i in Items.STASH_SIZE:
		var s: Control = SlotScript.new()
		s.kind = "stash"
		s.custom_minimum_size = Vector2(29, 29)
		s.clicked.connect(_on_stash_click)
		s.dropped.connect(_on_stash_drop)
		s.hovered.connect(_on_hover)
		sgrid.add_child(s)
		_stash_slots.append(s)
	var hint := Label.new()
	hint.text = "Orbs also work anywhere: right-click an orb in your bag, then click an item.\nEnhancement: +1..+10, rising failure chance & gold cost; from +5 a failure may drop a level (never destroys)."
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(hint)


func _on_slot_drop(_t: Control, data: Dictionary) -> void:
	select(data["inst"])


func _on_hover(s: Control, on: bool) -> void:
	if tooltip == null:
		return
	if on and not s.inst.is_empty():
		tooltip.show_gear(s.inst, player, s.get_global_rect().end)
	else:
		tooltip.hide_tip()


func _on_sell() -> void:
	if selected_uid >= 0:
		player.request_sell(selected_uid)


func _on_stash_put() -> void:
	if selected_uid >= 0:
		player.request_stash("put", selected_uid)


func _on_stash_click(sl: Control, _b: int, _sh: bool, _c: bool) -> void:
	if not sl.inst.is_empty():
		player.request_stash("take", int(sl.inst["uid"]))


func _on_stash_drop(_t: Control, data: Dictionary) -> void:
	player.request_stash("put", int(data["uid"]))


func set_player(p: Node) -> void:
	player = p


func select(inst: Dictionary) -> void:
	selected_uid = int(inst.get("uid", -1))
	refresh()


func _find_selected() -> Dictionary:
	if player == null or selected_uid < 0:
		return {}
	for inst in player.bag:
		if int(inst["uid"]) == selected_uid:
			return inst
	for sl in player.equipment:
		if not player.equipment[sl].is_empty() and int(player.equipment[sl]["uid"]) == selected_uid:
			return player.equipment[sl]
	return {}


func _apply(orb: String) -> void:
	if player and selected_uid >= 0:
		player.request_craft(orb, selected_uid)


func refresh() -> void:
	if player == null or _slot == null:
		return
	var inst := _find_selected()
	if inst.is_empty():
		selected_uid = -1
		_slot.clear()
		_info.text = "[color=#bbbbbb]Select an item: click it in your bag or paper doll, or drag it onto the slot.[/color]"
	else:
		_slot.set_gear(inst)
		var lines: Array = []
		var tip := Gear.tooltip(inst, player.class_id, player.level)
		for i in mini(tip.size(), 9):
			var t: String = str(tip[i][0]).replace("[", "[lb]")
			lines.append(("[b][color=#%s]%s[/color][/b]" if i == 0 else "[color=#%s]%s[/color]") % [(tip[i][1] as Color).to_html(false), t])
		_info.text = "\n".join(lines)
	var r := str(inst.get("rarity", ""))
	for orb in _orb_buttons:
		var b: Button = _orb_buttons[orb]
		var n := int(player.inventory.get(orb, 0))
		var label := "%s  x%d" % [Items.display_name(orb).replace(" (Huyen Tinh)", ""), n]
		var ok := not inst.is_empty() and n > 0
		if orb == "enhance_stone" and Dungeons.is_ticket(inst):
			label = "Enhance: not for tickets"
			ok = false
		elif orb == "enhance_stone" and not inst.is_empty():
			var u := int(inst.get("upg", 0))
			if u >= Gear.MAX_UPG:
				label = "Enhance: MAX (+10)"
				ok = false
			else:
				label = "Enhance +%d->+%d  %d%%  %dg  (x%d)" % [u, u + 1, roundi(Gear.ENHANCE_CHANCE[u] * 100.0), Gear.enhance_gold(u), n]
				ok = ok and player.gold >= Gear.enhance_gold(u)
		elif not inst.is_empty():
			var valid := {"orb_transmute": r == "normal", "orb_alteration": r == "magic", "orb_regal": r == "magic",
				"orb_chaos": r == "rare", "orb_exalt": r == "rare" and inst["mods"].size() < 6, "orb_scour": r in ["magic", "rare"],
				"orb_chisel": Dungeons.is_ticket(inst) and int(inst.get("q", 0)) < Dungeons.MAX_QUALITY}
			if r == "unique":
				valid = {}
			ok = ok and bool(valid.get(orb, false))
		b.text = label
		b.modulate = Color.WHITE if ok else Color(1, 1, 1, 0.45)
	var in_bag := false
	for x in player.bag:
		if int(x["uid"]) == selected_uid:
			in_bag = true
	_sell_btn.text = ("Sell for %d gold" % Gear.sell_price(inst)) if not inst.is_empty() else "Sell"
	_sell_btn.disabled = not in_bag
	_stash_btn.disabled = not in_bag
	_stash_label.text = "Shared stash  %d/%d  (click to take, drag items here to store)" % [player.stash.size(), Items.STASH_SIZE]
	for i in _stash_slots.size():
		if i < player.stash.size():
			_stash_slots[i].set_gear(player.stash[i])
		else:
			_stash_slots[i].clear()


func _process(_delta: float) -> void:
	if visible and is_instance_valid(player):
		if not player.near_blacksmith():
			visible = false
			if tooltip:
				tooltip.hide_tip()
