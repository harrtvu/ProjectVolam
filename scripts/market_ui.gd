extends PanelContainer
## Trade Broker panel (Sunny Meadow, press E next to the broker). Three tabs:
##   Browse - search filters, sorted + paged results with full tooltips, Buy
##   Sell   - click an item / stack in your bag (or drag it here), set a price, List
##   Mine   - your active listings (Cancel), the claim box (Collect) and sales history
## Every action is a request; the server (market_server.gd) validates and answers.

const SlotScript := preload("res://scripts/item_slot.gd")

var player: Node = null
var market: Node = null
var tooltip: Control = null
var tab := "browse"
var sell_uid := -1
var sell_stack := ""
var show_first_tip := false    # (screenshots) show the first result's tooltip
var _title: Label
var _tabs := {}
var _pages := {}
var _status: Label
# browse
var _text: LineEdit
var _cat: OptionButton
var _rarity: OptionButton
var _sort: OptionButton
var _max_req: SpinBox
var _usable: CheckBox
var _theme: OptionButton
var _tier_min: SpinBox
var _tier_max: SpinBox
var _stat: OptionButton
var _stat_min: SpinBox
var _price_min: SpinBox
var _price_max: SpinBox
var _rows: VBoxContainer
var _page_lbl: Label
var _page := 0
# sell
var _sell_slot: Control
var _sell_info: RichTextLabel
var _qty: SpinBox
var _price: SpinBox
var _fee_lbl: Label
# mine
var _claim_lbl: RichTextLabel
var _mine_rows: VBoxContainer
var _hist: RichTextLabel

const RARITY_OPTS := ["any", "normal", "magic", "rare", "unique"]


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.06, 0.96)
	sb.border_color = Color(0.5, 0.95, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(600, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_title = _label("Trade Broker  -  Player Market   (E / Esc to close)", Color(0.65, 1.0, 0.7), 13)
	vb.add_child(_title)
	var tb := HBoxContainer.new()
	vb.add_child(tb)
	for t in [["browse", "Browse / Buy"], ["sell", "Sell an item"], ["mine", "My Listings / Claim"]]:
		var b := _button(t[1], show_tab.bind(t[0]), 150)
		b.toggle_mode = true
		tb.add_child(b)
		_tabs[t[0]] = b
	_pages["browse"] = _build_browse()
	_pages["sell"] = _build_sell()
	_pages["mine"] = _build_mine()
	for k in _pages:
		vb.add_child(_pages[k])
	_status = _label("", Color(0.75, 0.75, 0.8), 10)
	vb.add_child(_status)
	show_tab("browse")


func set_player(p: Node, m: Node) -> void:
	player = p
	if market != m:
		market = m
		market.page_changed.connect(_refresh_browse)
		market.mine_changed.connect(_refresh_mine)


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
	b.custom_minimum_size = Vector2(w, 24)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


func _opt(items: Array, names: Dictionary = {}, w := 110) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 11)
	o.custom_minimum_size = Vector2(w, 24)
	for it in items:
		o.add_item(str(names.get(it, it)))
	return o


func _spin(lo: float, hi: float, v: float, w := 70, step := 1.0) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(w, 24)
	s.get_line_edit().add_theme_font_size_override("font_size", 11)
	return s


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	return h


# ---------------------------------------------------------------- browse

func _build_browse() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var r1 := _row()
	vb.add_child(r1)
	_text = LineEdit.new()
	_text.placeholder_text = "name contains..."
	_text.custom_minimum_size = Vector2(140, 24)
	_text.add_theme_font_size_override("font_size", 11)
	_text.text_submitted.connect(func(_t): search(0))
	r1.add_child(_text)
	_cat = _opt(Market.CATEGORIES, Market.CAT_NAMES, 130)
	r1.add_child(_cat)
	_rarity = _opt(RARITY_OPTS, {"any": "Any rarity", "normal": "Normal", "magic": "Magic", "rare": "Rare", "unique": "Unique"}, 100)
	r1.add_child(_rarity)
	_sort = _opt(Market.SORTS, Market.SORT_NAMES, 150)
	r1.add_child(_sort)
	var r2 := _row()
	vb.add_child(r2)
	r2.add_child(_label("Req lvl <="))
	_max_req = _spin(0, 99, 0, 60)
	r2.add_child(_max_req)
	_usable = CheckBox.new()
	_usable.text = "usable by my class"
	_usable.focus_mode = Control.FOCUS_NONE
	_usable.add_theme_font_size_override("font_size", 11)
	r2.add_child(_usable)
	var themes := ["any"] + Dungeons.ORDER
	var tn := {"any": "Any ticket theme"}
	for th in Dungeons.ORDER:
		tn[th] = Dungeons.theme_name(th)
	_theme = _opt(themes, tn, 130)
	r2.add_child(_theme)
	r2.add_child(_label("Tier"))
	_tier_min = _spin(0, Dungeons.MAX_TIER, 0, 55)
	r2.add_child(_tier_min)
	r2.add_child(_label("-"))
	_tier_max = _spin(0, Dungeons.MAX_TIER, 0, 55)
	r2.add_child(_tier_max)
	var r3 := _row()
	vb.add_child(r3)
	var sn := {"": "Any affix"}
	for st in Market.FILTER_STATS:
		if st != "":
			sn[st] = Stats.label(st)
	_stat = _opt(Market.FILTER_STATS, sn, 150)
	r3.add_child(_stat)
	r3.add_child(_label(">="))
	_stat_min = _spin(0, 999, 0, 60)
	r3.add_child(_stat_min)
	r3.add_child(_label("Price"))
	_price_min = _spin(0, Market.MAX_PRICE, 0, 80)
	r3.add_child(_price_min)
	r3.add_child(_label("-"))
	_price_max = _spin(0, Market.MAX_PRICE, 0, 80)
	r3.add_child(_price_max)
	r3.add_child(_button("Search", func(): search(0), 70))
	r3.add_child(_button("Reset", _reset_filters, 55))
	vb.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.custom_minimum_size = Vector2(0, 8 * 34)
	vb.add_child(_rows)
	var pr := _row()
	vb.add_child(pr)
	pr.add_child(_button("< Prev", func(): search(_page - 1), 70))
	_page_lbl = _label("", Color(0.8, 0.8, 0.85))
	_page_lbl.custom_minimum_size = Vector2(220, 0)
	_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.add_child(_page_lbl)
	pr.add_child(_button("Next >", func(): search(_page + 1), 70))
	return vb


func filters() -> Dictionary:
	return {"text": _text.text, "cat": Market.CATEGORIES[_cat.selected], "rarity": RARITY_OPTS[_rarity.selected],
		"sort": Market.SORTS[_sort.selected], "max_req": int(_max_req.value), "usable": _usable.button_pressed,
		"theme": (["any"] + Dungeons.ORDER)[_theme.selected], "tier_min": int(_tier_min.value), "tier_max": int(_tier_max.value),
		"stat": Market.FILTER_STATS[_stat.selected], "stat_min": _stat_min.value,
		"price_min": int(_price_min.value), "price_max": int(_price_max.value)}


## (screenshots / tests) set some filters from a dictionary like filters() returns.
func set_filters(f: Dictionary) -> void:
	_text.text = str(f.get("text", ""))
	_cat.select(maxi(0, Market.CATEGORIES.find(str(f.get("cat", "any")))))
	_rarity.select(maxi(0, RARITY_OPTS.find(str(f.get("rarity", "any")))))
	_sort.select(maxi(0, Market.SORTS.find(str(f.get("sort", "price_asc")))))
	_max_req.value = int(f.get("max_req", 0))
	_usable.button_pressed = bool(f.get("usable", false))
	_stat.select(maxi(0, Market.FILTER_STATS.find(str(f.get("stat", "")))))
	_stat_min.value = float(f.get("stat_min", 0))
	_price_min.value = int(f.get("price_min", 0))
	_price_max.value = int(f.get("price_max", 0))


func _reset_filters() -> void:
	set_filters({})
	_theme.select(0)
	_tier_min.value = 0
	_tier_max.value = 0
	search(0)


func search(pg: int) -> void:
	if player == null:
		return
	var f := filters()
	f["page"] = maxi(0, pg)
	player.request_market("browse", {"filters": f})


func _refresh_browse() -> void:
	if market == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	var pg: Dictionary = market.page
	_page = int(pg["page"])
	_page_lbl.text = "Page %d / %d   (%d listing%s)" % [_page + 1, int(pg["pages"]), int(pg["total"]), "" if int(pg["total"]) == 1 else "s"]
	if pg["rows"].is_empty():
		_rows.add_child(_label("No listings match these filters.", Color(0.6, 0.6, 0.65)))
	for l in pg["rows"]:
		var h := _row()
		_rows.add_child(h)
		h.add_child(_listing_slot(l))
		var item: Dictionary = l["item"]
		var col: Color = Color(0.75, 0.95, 1.0) if Market.is_stack(item) else Gear.RARITY_COLOR.get(str(item.get("rarity", "normal")), Color.WHITE)
		var n := _label(Market.item_name(item), col, 12)
		n.custom_minimum_size = Vector2(230, 0)
		n.clip_text = true
		h.add_child(n)
		var info := ""
		if not Market.is_stack(item):
			info = ("T%d" % Dungeons.tier_of(item)) if Dungeons.is_ticket(item) else ("Lv %d" % Gear.req_level(item))
		var il := _label(info, Color(0.7, 0.7, 0.75), 10)
		il.custom_minimum_size = Vector2(40, 0)
		h.add_child(il)
		var pl := _label("%d g" % int(l["price"]), Color(1, 0.85, 0.3), 12)
		pl.custom_minimum_size = Vector2(80, 0)
		h.add_child(pl)
		var sl := _label(str(l["seller_name"]), Color(0.6, 0.75, 0.65), 10)
		sl.custom_minimum_size = Vector2(80, 0)
		h.add_child(sl)
		var b := _button("Buy", _buy.bind(int(l["id"]), int(l["price"])), 55)
		b.disabled = player != null and (str(l["seller"]) == player.account_key or player.gold < int(l["price"]))
		h.add_child(b)
	if tooltip and show_first_tip and not pg["rows"].is_empty():
		var first: Dictionary = pg["rows"][0]
		await get_tree().process_frame
		await get_tree().process_frame
		if is_inside_tree() and _rows.get_child_count() > 0:
			var r: Control = _rows.get_child(_rows.get_child_count() - pg["rows"].size())
			tooltip.show_listing(first, player, r.global_position + Vector2(r.size.x * 0.45, 4))


func _listing_slot(l: Dictionary) -> Control:
	var s := SlotScript.new()
	s.kind = "listing"
	s.custom_minimum_size = Vector2(32, 32)
	var item: Dictionary = l["item"]
	if Market.is_stack(item):
		s.set_stack(str(item["stack"]), int(item["n"]))
	else:
		s.set_gear(item)
	s.hovered.connect(func(_s, on):
		if tooltip == null:
			return
		if on:
			tooltip.show_listing(l, player, s.get_global_mouse_position())
		else:
			tooltip.hide_tip())
	return s


func _buy(id: int, price: int) -> void:
	player.request_market("buy", {"id": id, "price": price})


# ---------------------------------------------------------------- sell

func _build_sell() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.add_child(_label("Click an item or a currency stack in your bag (or drag it onto the slot), set a price and list it.\nThe item waits in escrow at the broker until someone buys it; your gold goes to your claim box.", Color(0.7, 0.7, 0.75), 10))
	var h := _row()
	vb.add_child(h)
	_sell_slot = SlotScript.new()
	_sell_slot.kind = "market"
	_sell_slot.placeholder = "item"
	_sell_slot.custom_minimum_size = Vector2(64, 64)
	_sell_slot.dropped.connect(func(_t, d): select_uid(int(d.get("uid", -1))))
	h.add_child(_sell_slot)
	_sell_info = RichTextLabel.new()
	_sell_info.bbcode_enabled = true
	_sell_info.fit_content = true
	_sell_info.scroll_active = false
	_sell_info.custom_minimum_size = Vector2(500, 64)
	_sell_info.add_theme_font_size_override("normal_font_size", 11)
	h.add_child(_sell_info)
	var r := _row()
	vb.add_child(r)
	r.add_child(_label("Quantity"))
	_qty = _spin(1, 9999, 1, 80)
	_qty.value_changed.connect(func(_v): _refresh_sell())
	r.add_child(_qty)
	r.add_child(_label("Price (gold)"))
	_price = _spin(1, Market.MAX_PRICE, 100, 110)
	_price.value_changed.connect(func(_v): _refresh_sell())
	r.add_child(_price)
	r.add_child(_button("List it", _list, 80))
	_fee_lbl = _label("", Color(1, 0.85, 0.4), 11)
	vb.add_child(_fee_lbl)
	return vb


func select_uid(uid: int) -> void:
	sell_uid = uid
	sell_stack = ""
	_refresh_sell()


func select_stack(id: String) -> void:
	sell_stack = id
	sell_uid = -1
	_qty.value = int(player.inventory.get(id, 1)) if player else 1
	_refresh_sell()


func _refresh_sell() -> void:
	if player == null or _sell_slot == null:
		return
	var why := ""
	_sell_slot.clear()
	if sell_stack != "":
		var have := int(player.inventory.get(sell_stack, 0))
		if have <= 0:
			sell_stack = ""
		else:
			_qty.max_value = have
			_sell_slot.set_stack(sell_stack, int(_qty.value))
			why = Market.tradeable_reason({"stack": sell_stack, "n": int(_qty.value)})
			_sell_info.text = "[b]%s[/b]  (you have %d)\n%s" % [Items.display_name(sell_stack), have, Items.info(sell_stack).get("desc", "")]
	var inst := {}
	if sell_uid >= 0:
		for it in player.bag:
			if int(it["uid"]) == sell_uid:
				inst = it
		if inst.is_empty():
			sell_uid = -1
		else:
			_sell_slot.set_gear(inst)
			why = Market.tradeable_reason(inst)
			var tip := Gear.tooltip(inst, player.class_id, player.level)
			var lines: Array = []
			for i in mini(tip.size(), 6):
				lines.append("[color=#%s]%s[/color]" % [tip[i][1].to_html(false), str(tip[i][0]).replace("[", "[lb]")])
			_sell_info.text = "\n".join(lines)
	_qty.editable = sell_stack != ""
	if sell_uid < 0 and sell_stack == "":
		_sell_info.text = "[color=#999999]No item selected. Click one in your bag (I).[/color]"
	var p := int(_price.value)
	var t := "Listing fee: %d gold (%d%%, min 1)   -   if it sells: %d tax (%d%%), you receive %d gold   -   active listings %d/%d" % [
		Market.fee(p), roundi(Market.FEE_PCT), Market.tax(p), roundi(Market.TAX_PCT), p - Market.tax(p),
		market.mine["listings"].size() if market else 0, int(market.mine.get("max", Market.MAX_LISTINGS)) if market else Market.MAX_LISTINGS]
	if why != "":
		t = "Can't list: " + why
	_fee_lbl.text = t
	_fee_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.45) if why != "" else Color(1, 0.85, 0.4))


func _list() -> void:
	if sell_stack != "":
		player.request_market("list", {"stack": sell_stack, "n": int(_qty.value), "price": int(_price.value)})
	elif sell_uid >= 0:
		player.request_market("list", {"uid": sell_uid, "price": int(_price.value)})
	sell_uid = -1
	sell_stack = ""


# ---------------------------------------------------------------- mine

func _build_mine() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	var h := _row()
	vb.add_child(h)
	_claim_lbl = RichTextLabel.new()
	_claim_lbl.bbcode_enabled = true
	_claim_lbl.fit_content = true
	_claim_lbl.scroll_active = false
	_claim_lbl.custom_minimum_size = Vector2(440, 36)
	_claim_lbl.add_theme_font_size_override("normal_font_size", 11)
	h.add_child(_claim_lbl)
	h.add_child(_button("Collect all", func(): player.request_market("claim"), 110))
	vb.add_child(_label("Active listings", Color(0.65, 1.0, 0.7), 12))
	_mine_rows = VBoxContainer.new()
	_mine_rows.add_theme_constant_override("separation", 2)
	vb.add_child(_mine_rows)
	vb.add_child(_label("History (sold / bought / expired / cancelled)", Color(0.65, 1.0, 0.7), 12))
	_hist = RichTextLabel.new()
	_hist.bbcode_enabled = true
	_hist.fit_content = true
	_hist.scroll_active = false
	_hist.custom_minimum_size = Vector2(560, 20)
	_hist.add_theme_font_size_override("normal_font_size", 10)
	vb.add_child(_hist)
	return vb


static func _dur(sec: int) -> String:
	if sec >= 3600:
		return "%dh %02dm" % [sec / 3600, (sec % 3600) / 60]
	return "%dm %02ds" % [sec / 60, sec % 60]


func _refresh_mine() -> void:
	if market == null:
		return
	var m: Dictionary = market.mine
	var c: Dictionary = m["claims"]
	var items: Array = []
	for it in c.get("items", []):
		items.append(Gear.display_name(it))
	for id in c.get("stacks", {}):
		items.append("%d x %s" % [int(c["stacks"][id]), Items.display_name(str(id))])
	_claim_lbl.text = "[b]Claim box:[/b] [color=#ffd84d]%d gold[/color]%s" % [int(c.get("gold", 0)),
		("  +  " + ", ".join(items)) if not items.is_empty() else "  (no items)"]
	for ch in _mine_rows.get_children():
		ch.queue_free()
	var now := int(m.get("now", Time.get_unix_time_from_system()))
	if m["listings"].is_empty():
		_mine_rows.add_child(_label("You have no active listings.", Color(0.6, 0.6, 0.65)))
	for l in m["listings"]:
		var h := _row()
		_mine_rows.add_child(h)
		h.add_child(_listing_slot(l))
		var item: Dictionary = l["item"]
		var col: Color = Color(0.75, 0.95, 1.0) if Market.is_stack(item) else Gear.RARITY_COLOR.get(str(item.get("rarity", "normal")), Color.WHITE)
		var n := _label(Market.item_name(item), col, 12)
		n.custom_minimum_size = Vector2(250, 0)
		n.clip_text = true
		h.add_child(n)
		var pl := _label("%d g" % int(l["price"]), Color(1, 0.85, 0.3), 12)
		pl.custom_minimum_size = Vector2(80, 0)
		h.add_child(pl)
		var el := _label("expires in " + _dur(maxi(0, int(l["expires"]) - now)), Color(0.7, 0.7, 0.75), 10)
		el.custom_minimum_size = Vector2(110, 0)
		h.add_child(el)
		h.add_child(_button("Cancel", func(): player.request_market("cancel", {"id": int(l["id"])}), 60))
	var lines: Array = []
	var hist: Array = m["history"].duplicate()
	hist.reverse()
	for e in hist.slice(0, 8):
		match str(e.get("kind", "")):
			"sold":
				lines.append("[color=#9fff9f]SOLD[/color] %s to %s for %d gold (you get %d after tax)" % [e["what"], e.get("buyer", "?"), int(e["price"]), int(e["net"])])
			"bought":
				lines.append("[color=#9fd0ff]BOUGHT[/color] %s from %s for %d gold" % [e["what"], e.get("seller", "?"), int(e["price"])])
			"expired":
				lines.append("[color=#ffb070]EXPIRED[/color] %s (returned to the claim box)" % e["what"])
			_:
				lines.append("[color=#aaaaaa]CANCELLED[/color] %s" % e["what"])
	_hist.text = "\n".join(lines) if not lines.is_empty() else "[color=#888888]Nothing yet.[/color]"
	_refresh_sell()


func show_tab(t: String) -> void:
	tab = t
	for k in _pages:
		_pages[k].visible = k == t
		_tabs[k].button_pressed = k == t
	if player:
		if t == "browse":
			search(_page)
		else:
			player.request_market("mine")
	_refresh_sell()


func refresh() -> void:
	if visible and tab == "sell":
		_refresh_sell()
	if _status and player:
		_status.text = "Gold: %d   -   listing fee %d%% (min 1), sales tax %d%%, listings last %s" % [player.gold, roundi(Market.FEE_PCT),
			roundi(Market.TAX_PCT), _dur(Market.DURATION)]
