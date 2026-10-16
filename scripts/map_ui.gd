extends PanelContainer
## Dungeon panels in Sunny Meadow (press E next to them):
##   merchant - buy Dungeon Tickets (T1 up to your unlocked tier) and take the daily free ticket
##   device   - put a ticket in the Map Device (click it in your bag), check its mods / IIQ / IIR,
##              open the portal; shows your open run (portals left, completed)
## Everything is validated on the server (instances.gd).

const SlotScript := preload("res://scripts/item_slot.gd")

var player: Node = null
var tooltip: Control = null
var mode := "merchant"
var selected_uid := -1
var _title: Label
var _body: VBoxContainer
var _slot: Control
var _info: RichTextLabel
var _status: RichTextLabel
var _open_btn: Button
var _close_btn: Button
var _rows := {}     # theme -> {opt, price, buy}
var _free_btn: Button
var _free_opt: OptionButton


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	sb.border_color = Color(0.55, 0.75, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(440, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_title.add_theme_font_size_override("font_size", 13)
	vb.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 5)
	vb.add_child(_body)


func set_player(p: Node) -> void:
	player = p


func open(m: String) -> void:
	mode = m
	for c in _body.get_children():
		c.queue_free()
	_rows.clear()
	if mode == "merchant":
		_build_merchant()
	else:
		_build_device()
	refresh()


func _label(text: String, col := Color(0.85, 0.85, 0.85), size := 11) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, w := 90) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 26)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


func _build_merchant() -> void:
	_title.text = "Ticket Merchant  -  Dungeon Tickets   (E / Esc to close)"
	_body.add_child(_label("Sells tickets for UNLOCKED Atlas nodes up to T%d (press M for the Atlas).\nHigher tiers drop inside dungeons; bosses favour tickets for adjacent nodes." % Atlas.MERCHANT_CAP, Color(0.7, 0.7, 0.75), 10))
	for th in Dungeons.ORDER:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		_body.add_child(hb)
		var ic := TextureRect.new()
		ic.texture = Items.icon("ticket_" + th)
		ic.custom_minimum_size = Vector2(24, 24)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(ic)
		var n := _label(Dungeons.theme_name(th), Classes.color(th).lerp(Color.WHITE, 0.3), 12)
		n.custom_minimum_size = Vector2(120, 0)
		hb.add_child(n)
		var opt := OptionButton.new()
		opt.focus_mode = Control.FOCUS_NONE
		opt.add_theme_font_size_override("font_size", 11)
		opt.custom_minimum_size = Vector2(60, 24)
		opt.item_selected.connect(func(_i): refresh())
		hb.add_child(opt)
		var price := _label("", Color(1, 0.85, 0.3))
		price.custom_minimum_size = Vector2(80, 0)
		hb.add_child(price)
		var buy := _button("Buy", _buy.bind(th), 60)
		hb.add_child(buy)
		_rows[th] = {"opt": opt, "price": price, "buy": buy}
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 8)
	_body.add_child(fr)
	_free_opt = OptionButton.new()
	_free_opt.focus_mode = Control.FOCUS_NONE
	_free_opt.add_theme_font_size_override("font_size", 11)
	for th in Dungeons.ORDER:
		_free_opt.add_item(Dungeons.theme_name(th))
	fr.add_child(_free_opt)
	_free_btn = _button("Take the daily free ticket", _free, 200)
	fr.add_child(_free_btn)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size = Vector2(410, 20)
	_status.add_theme_font_size_override("normal_font_size", 10)
	_body.add_child(_status)


func _build_device() -> void:
	_title.text = "Map Device  -  open a Dungeon Ticket   (E / Esc to close)"
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	_body.add_child(hb)
	_slot = SlotScript.new()
	_slot.kind = "map"
	_slot.placeholder = "ticket"
	_slot.custom_minimum_size = Vector2(64, 64)
	_slot.dropped.connect(func(_t, data): select_uid(int(data.get("uid", -1))))
	hb.add_child(_slot)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.custom_minimum_size = Vector2(340, 60)
	_info.add_theme_font_size_override("normal_font_size", 11)
	_info.add_theme_font_size_override("bold_font_size", 13)
	hb.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	_open_btn = _button("Open portal (%d portals)" % Dungeons.PORTALS, _open, 200)
	row.add_child(_open_btn)
	_close_btn = _button("Close my dungeon", _close, 160)
	row.add_child(_close_btn)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size = Vector2(410, 20)
	_status.add_theme_font_size_override("normal_font_size", 11)
	_body.add_child(_status)


func select(inst: Dictionary) -> void:
	if Dungeons.is_ticket(inst):
		select_uid(int(inst["uid"]))


func select_uid(uid: int) -> void:
	selected_uid = uid
	refresh()


func _find_selected() -> Dictionary:
	if player == null:
		return {}
	for inst in player.bag:
		if int(inst["uid"]) == selected_uid:
			return inst
	return {}


func _buy(th: String) -> void:
	var opt: OptionButton = _rows[th]["opt"]
	player.request_dungeon("buy", {"theme": th, "tier": opt.get_item_id(maxi(0, opt.selected))})


func _free() -> void:
	player.request_dungeon("free", {"theme": Dungeons.ORDER[_free_opt.selected]})


func _open() -> void:
	if selected_uid >= 0:
		player.request_dungeon("open", {"uid": selected_uid})


func _close() -> void:
	player.request_dungeon("close")


func refresh() -> void:
	if player == null or _status == null or not is_instance_valid(_status):
		return
	var ri: Dictionary = player.run_info
	var run_txt := ""
	if not ri.is_empty():
		run_txt = "[color=#9fd0ff]Your open dungeon: %s  -  %d portal%s left%s  (iiq +%d%%  iir +%d%%)[/color]" % [ri["name"], ri["portals"],
			"" if int(ri["portals"]) == 1 else "s", "  -  COMPLETED" if ri["completed"] else "", roundi(ri["iiq"]), roundi(ri["iir"])]
	if mode == "merchant":
		for th in _rows:
			var opt: OptionButton = _rows[th]["opt"]
			var tiers: Array = Atlas.REGION_TIERS.filter(func(t): return Atlas.merchant_sells(player.atlas, th, t))
			if opt.item_count != tiers.size():
				var keep := opt.selected
				opt.clear()
				for t in tiers:
					opt.add_item("T%d" % t, t)
				opt.select(clampi(keep, 0, tiers.size() - 1))
			var tier := opt.get_item_id(maxi(0, opt.selected))
			_rows[th]["price"].text = "%d gold" % Dungeons.price(tier)
			_rows[th]["buy"].disabled = player.gold < Dungeons.price(tier)
		var free_ok: bool = player.free_day != Time.get_date_string_from_system()
		_free_btn.disabled = not free_ok
		_free_btn.text = "Take the daily free ticket" if free_ok else "Free ticket taken today"
		_status.text = "Gold: [color=#ffd84d]%d[/color]   Atlas: %d completed (+%d%% item quantity in dungeons)\n%s" % [player.gold,
			Dungeons.completed_nodes(player.atlas), roundi(Dungeons.atlas_iiq(player.atlas)), run_txt]
		return
	var inst := _find_selected()
	if inst.is_empty():
		selected_uid = -1
		_slot.clear()
		_info.text = "[color=#bbbbbb]Click a Dungeon Ticket in your bag (or drag it here). Craft it first at the blacksmith: orbs add map mods (more IIQ / IIR), a Chisel adds quality.[/color]"
	else:
		_slot.set_gear(inst)
		var lines: Array = []
		var tip := Dungeons.tooltip(inst, player.atlas)
		for i in tip.size():
			var t: String = str(tip[i][0]).replace("[", "[lb]")
			lines.append(("[b][color=#%s]%s[/color][/b]" if i == 0 else "[color=#%s]%s[/color]") % [(tip[i][1] as Color).to_html(false), t])
		_info.text = "\n".join(lines)
	_open_btn.disabled = inst.is_empty() or not ri.is_empty()
	_close_btn.disabled = ri.is_empty() or int(ri.get("inside", 0)) > 0
	_status.text = run_txt if run_txt != "" else "[color=#888888]Runs are solo: only you can enter your portals. Dying sends you to town; each entry uses a portal.[/color]"


func _process(_delta: float) -> void:
	if visible and is_instance_valid(player):
		var near: bool = player.near_merchant() if mode == "merchant" else player.near_map_device()
		if not near:
			visible = false
