extends PanelContainer
const Vendor := preload("res://scripts/vendor.gd")
## NPC vendor panel (press E next to the Vendor in Sunny Meadow or in your hideout).
## Left: the rotating stock (Buy). Right: sell - click an item / stack in your bag
## (or drag it onto the slot) to SELECT it, then press Sell. Anything above normal rarity asks
## for a confirmation first; stacks get a quantity picker. The server (vendor_server.gd) validates.

signal ui_log(msg: String)

const SlotScript := preload("res://scripts/item_slot.gd")

var player: Node = null
var vendor: Node = null
var tooltip: Control = null
var sell_uid := -1
var sell_stack := ""
var _rows: VBoxContainer
var _rot_lbl: Label
var _sell_slot: Control
var _sell_info: RichTextLabel
var _sell_btn: Button
var _status: Label
var _buy_rows: Array = []   # [button, price label, price, qty] per stock row
var _warn_t := 0.0
var _t := 0.0
var sell_qty := 1                 # stacks: how many to sell
var _qty_row: HBoxContainer
var _qty_lbl: Label
var _confirm_row: HBoxContainer
var _confirm_lbl: Label
var _sel_ms := 0                  # when the selection last changed (a Sell press right after it is ignored)
const SELL_ARM_MS := 350


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.04, 0.96)
	sb.border_color = Color(1.0, 0.8, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(600, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Vendor  -  buy supplies, sell your loot   (E / Esc to close)", Color(1.0, 0.85, 0.5), 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_status = _label("", Color(1, 0.85, 0.3), 13)   # your gold, top-right (the panel covers the HUD's gold line)
	head.add_child(_status)
	_rot_lbl = _label("", Color(0.75, 0.75, 0.8), 10)
	vb.add_child(_rot_lbl)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(580, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_rows)
	vb.add_child(HSeparator.new())
	vb.add_child(_label("Sell: click an item or a stack in your bag (or drag it here) to select it, then press Sell.", Color(0.7, 0.7, 0.75), 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	vb.add_child(h)
	_sell_slot = SlotScript.new()
	_sell_slot.kind = "vendor"
	_sell_slot.placeholder = "sell"
	_sell_slot.custom_minimum_size = Vector2(56, 56)
	_sell_slot.dropped.connect(func(_t2, d): select_uid(int(d.get("uid", -1))))
	h.add_child(_sell_slot)
	_sell_info = RichTextLabel.new()
	_sell_info.bbcode_enabled = true
	_sell_info.fit_content = true
	_sell_info.scroll_active = false
	_sell_info.custom_minimum_size = Vector2(400, 56)
	_sell_info.add_theme_font_size_override("normal_font_size", 11)
	h.add_child(_sell_info)
	var right := VBoxContainer.new()
	h.add_child(right)
	_qty_row = HBoxContainer.new()
	_qty_row.add_theme_constant_override("separation", 2)
	right.add_child(_qty_row)
	_qty_row.add_child(_button("-", func(): set_qty(sell_qty - 1), 24))
	_qty_lbl = _label("1", Color.WHITE, 12)
	_qty_lbl.custom_minimum_size = Vector2(34, 0)
	_qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_row.add_child(_qty_lbl)
	_qty_row.add_child(_button("+", func(): set_qty(sell_qty + 1), 24))
	_qty_row.add_child(_button("All", func(): set_qty(999999), 34))
	_qty_row.visible = false
	_sell_btn = _button("Sell", _sell, 110)
	right.add_child(_sell_btn)
	_confirm_row = HBoxContainer.new()
	_confirm_row.add_theme_constant_override("separation", 6)
	vb.add_child(_confirm_row)
	_confirm_lbl = _label("", Color(1, 0.75, 0.4), 11)
	_confirm_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_row.add_child(_confirm_lbl)
	_confirm_row.add_child(_button("Yes, sell", confirm_sell, 80))
	_confirm_row.add_child(_button("Cancel", cancel_sell, 64))
	_confirm_row.visible = false



func set_player(p: Node, v: Node) -> void:
	player = p
	if vendor != v:
		vendor = v
		vendor.stock_changed.connect(_refresh_stock)


func _label(text: String, col := Color(0.85, 0.85, 0.85), size := 11) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable, w := 70) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 24)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


func _refresh_stock() -> void:
	if vendor == null or _rows == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	_buy_rows.clear()
	for e in vendor.stock:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		_rows.add_child(h)
		var s := SlotScript.new()
		s.kind = "stock"
		s.custom_minimum_size = Vector2(32, 32)
		if e.has("item"):
			s.set_gear(e["item"])
		else:
			s.set_stack(str(e["stack"]), int(e["qty"]))
		s.hovered.connect(_hover.bind(e, s))
		h.add_child(s)
		var col: Color = Gear.RARITY_COLOR.get(str(e["item"].get("rarity", "normal")), Color.WHITE) if e.has("item") else Color(0.75, 0.95, 1.0)
		var n := _label(Vendor.entry_name(e), col, 12)
		n.custom_minimum_size = Vector2(250, 0)
		n.clip_text = true
		h.add_child(n)
		var info := ("Lv %d" % Gear.req_level(e["item"])) if e.has("item") else ("%d left" % int(e["qty"]))
		var il := _label(info, Color(0.7, 0.7, 0.75), 10)
		il.custom_minimum_size = Vector2(60, 0)
		h.add_child(il)
		var pl := _label("%d g" % int(e["price"]), Color(1, 0.85, 0.3), 12)
		pl.custom_minimum_size = Vector2(70, 0)
		h.add_child(pl)
		var b := _button("Sold out" if int(e["qty"]) <= 0 else "Buy", _buy.bind(int(e["id"])), 70)
		b.disabled = int(e["qty"]) <= 0
		h.add_child(b)
		_buy_rows.append([b, pl, int(e["price"]), int(e["qty"])])
	refresh()


func _hover(_slot: Control, on: bool, e: Dictionary, s: Control) -> void:
	if tooltip == null:
		return
	if not on:
		tooltip.hide_tip()
	elif e.has("item"):
		tooltip.show_gear(e["item"], player, s.get_global_mouse_position())
	else:
		tooltip.show_stack(str(e["stack"]), int(e["qty"]), s.get_global_mouse_position())


func _buy(id: int) -> void:
	for e in (vendor.stock if vendor else []):
		if int(e.get("id", -1)) == id and player.gold < int(e["price"]):
			_status.text = "Not enough gold (you have %d, it costs %d)" % [player.gold, int(e["price"])]
			_status.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
			_warn_t = 3.0
			if player._main:
				player._main._log("vendor panel: Not enough gold for #%d (%d/%d)" % [id, player.gold, int(e["price"])])
	player.request_vendor("buy", {"id": id, "n": 1})   # the server checks again (and logs the rejection)


## Rows you can't afford look greyed out (price in red) but stay clickable, so a click explains why.
func _update_affordable() -> void:
	for r in _buy_rows:
		if not is_instance_valid(r[0]):
			continue
		var poor: bool = player != null and player.gold < int(r[2]) and int(r[3]) > 0
		r[0].modulate = Color(1, 1, 1, 0.45) if poor else Color.WHITE
		r[1].add_theme_color_override("font_color", Color(1, 0.45, 0.4) if poor else Color(1, 0.85, 0.3))


func select_uid(uid: int) -> void:
	sell_uid = uid
	sell_stack = ""
	_selected()


func select_stack(id: String) -> void:
	sell_stack = id
	sell_uid = -1
	sell_qty = 1
	_selected()


func _selected() -> void:
	_sel_ms = Time.get_ticks_msec()
	_confirm_row.visible = false
	refresh()
	ui_log.emit("vendor: selected %s (not sold)" % _sel_name())


func set_qty(n: int) -> void:
	if sell_stack == "" or player == null:
		return
	sell_qty = clampi(n, 1, maxi(1, int(player.inventory.get(sell_stack, 0))))
	refresh()


func _sel_inst() -> Dictionary:
	if player != null and sell_uid >= 0:
		for it in player.bag:
			if int(it["uid"]) == sell_uid:
				return it
	return {}


func _sel_name() -> String:
	if sell_stack != "":
		return "%d x %s" % [sell_qty, Items.display_name(sell_stack)]
	var inst := _sel_inst()
	return "[%s] %s" % [inst["rarity"], Gear.display_name(inst)] if not inst.is_empty() else "nothing"


## The Sell button. Gear above normal rarity asks first ("Yes, sell" / "Cancel").
func _sell() -> void:
	if sell_stack == "" and sell_uid < 0:
		return
	if Time.get_ticks_msec() - _sel_ms < SELL_ARM_MS:   # a double-click on the item must not reach the button
		ui_log.emit("vendor: Sell pressed %d ms after selecting - ignored" % (Time.get_ticks_msec() - _sel_ms))
		return
	var inst := _sel_inst()
	if not inst.is_empty() and str(inst.get("rarity", "normal")) != "normal":
		_confirm_lbl.text = "Sell %s for %d gold? This can't be undone." % [Gear.display_name(inst), Gear.sell_price(inst)]
		_confirm_row.visible = true
		ui_log.emit("vendor: confirm asked for %s" % _sel_name())
		return
	_do_sell()


func confirm_sell() -> void:
	if _confirm_row.visible:
		_confirm_row.visible = false
		_do_sell()


func cancel_sell() -> void:
	_confirm_row.visible = false
	ui_log.emit("vendor: sale of %s cancelled" % _sel_name())


func _do_sell() -> void:
	ui_log.emit("vendor: selling %s" % _sel_name())
	if sell_stack != "":
		player.request_vendor("sell", {"stack": sell_stack, "n": sell_qty})
	elif sell_uid >= 0:
		player.request_vendor("sell", {"uid": sell_uid})
	sell_uid = -1
	sell_stack = ""
	sell_qty = 1


func _process(delta: float) -> void:
	_t -= delta
	if _warn_t > 0.0:
		_warn_t -= delta
		if _warn_t <= 0.0:
			refresh()
	if visible and _t <= 0.0 and vendor:
		_t = 1.0
		var left: int = maxi(0, vendor.next_rotation - int(Time.get_unix_time_from_system()))
		_rot_lbl.text = "Stock rotates in %dh %02dm %02ds (and every new day). Stock and prices are the same for everyone." % [left / 3600, (left / 60) % 60, left % 60]


func refresh() -> void:
	if player == null or _sell_slot == null:
		return
	_sell_slot.clear()
	var price := 0
	if sell_stack != "":
		var have := int(player.inventory.get(sell_stack, 0))
		var each := int(Items.info(sell_stack).get("sell", 0))
		if have <= 0:
			sell_stack = ""
		else:
			sell_qty = clampi(sell_qty, 1, have)
			_sell_slot.set_stack(sell_stack, have)
			price = sell_qty * each
			_qty_lbl.text = str(sell_qty)
			_sell_info.text = "[b]%s[/b]  sell %d of %d\n%s" % [Items.display_name(sell_stack), sell_qty, have, "The vendor pays %d gold each." % each if each > 0 else "[color=#ff8070]The vendor won't buy this.[/color]"]
	if sell_uid >= 0:
		var inst := {}
		for it in player.bag:
			if int(it["uid"]) == sell_uid:
				inst = it
		if inst.is_empty():
			sell_uid = -1
		else:
			_sell_slot.set_gear(inst)
			price = Gear.sell_price(inst)
			var tip := Gear.tooltip(inst, player.class_id, player.level)
			var lines: Array = []
			for i in mini(tip.size(), 4):
				lines.append("[color=#%s]%s[/color]" % [tip[i][1].to_html(false), str(tip[i][0]).replace("[", "[lb]")])
			_sell_info.text = "\n".join(lines)
	_qty_row.visible = sell_stack != ""
	if sell_uid < 0 and sell_stack == "":
		_confirm_row.visible = false
		_sell_info.text = "[color=#999999]Nothing selected. Click an item in your bag.[/color]"
	_sell_btn.text = "Sell for %d gold" % price if price > 0 else "Sell"
	_sell_btn.disabled = price <= 0
	_update_affordable()
	if _warn_t <= 0.0:
		_status.text = "Gold: %d" % player.gold
		_status.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
