extends PanelContainer
## Inventory window (I): paper-doll equipment (10 slots) + a 40-slot bag.
##   click gear = equip (or select it for the blacksmith while that panel is open)
##   click potion = drink, right-click (or click) an orb = pick it up, then click an item to apply
##   shift+click = drop on the ground, ctrl+click twice = destroy
##   drag & drop: bag <-> paper doll, onto Drop / Destroy, onto the blacksmith slot / stash
## Every action is a request; the server validates it and pushes the new state back.

const SlotScript := preload("res://scripts/item_slot.gd")
const DOLL := {   # slot -> position in the paper doll (px)
	"helmet": Vector2(76, 0), "amulet": Vector2(124, 10), "weapon": Vector2(20, 54), "body": Vector2(76, 50),
	"offhand": Vector2(132, 54), "gloves": Vector2(20, 104), "belt": Vector2(76, 100), "ring1": Vector2(132, 104),
	"ring2": Vector2(132, 150), "boots": Vector2(76, 150)}

var player: Node = null
var tooltip: Control = null      # item_tooltip.gd (owned by Main's HUD)
var smith: Control = null        # blacksmith panel (owned by Main's HUD)
var map_ui: Control = null       # Map Device panel (click a ticket to load it)
var vendor_ui: Control = null    # Vendor panel (click an item / stack to select it for selling)
var apply_orb := ""              # orb picked up with right-click
var _gold_label: Label
var _stats_label: Label
var _left: Control                 # paper doll + stats column (hidden in compact mode)
var _status: Label
var _doll := {}
var _bag_slots: Array = []
var _drop_zone: Control
var _destroy_zone: Control
var _destroy_armed := -1
var _destroy_armed_ms := 0
var _hover: Control = null


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.10, 0.94)
	sb.border_color = Color(0.85, 0.7, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := Label.new()
	title.text = "Inventory  (I)"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var coin := TextureRect.new()
	coin.texture = Items.icon("gold")
	coin.custom_minimum_size = Vector2(20, 20)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(coin)
	_gold_label = Label.new()
	top.add_child(_gold_label)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	# paper doll
	var left := VBoxContainer.new()
	hb.add_child(left)
	_left = left
	var doll := Control.new()
	doll.custom_minimum_size = Vector2(176, 196)
	left.add_child(doll)
	var fig := DollFigure.new()
	fig.size = doll.custom_minimum_size
	doll.add_child(fig)
	for sl in DOLL:
		var s: Control = SlotScript.new()
		s.kind = "equip"
		s.key = sl
		s.placeholder = Items.SLOT_NAMES[sl]
		s.position = DOLL[sl]
		s.size = Vector2(40, 40)
		_wire(s)
		doll.add_child(s)
		_doll[sl] = s
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.modulate = Color(1, 1, 1, 0.85)
	_stats_label.custom_minimum_size = Vector2(176, 0)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	left.add_child(_stats_label)
	# bag
	var right := VBoxContainer.new()
	hb.add_child(right)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	right.add_child(grid)
	for i in Items.BAG_SIZE:
		var s: Control = SlotScript.new()
		s.kind = "bag"
		s.key = str(i)
		_wire(s)
		grid.add_child(s)
		_bag_slots.append(s)
	var zones := HBoxContainer.new()
	zones.add_theme_constant_override("separation", 6)
	right.add_child(zones)
	_drop_zone = _zone_slot("drop", "Drop")
	zones.add_child(_drop_zone)
	_destroy_zone = _zone_slot("destroy", "Destroy")
	zones.add_child(_destroy_zone)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(240, 0)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zones.add_child(_status)


func _zone_slot(k: String, caption: String) -> Control:
	var s: Control = SlotScript.new()
	s.kind = "zone"
	s.key = k
	s.placeholder = caption
	s.custom_minimum_size = Vector2(58, 34)
	_wire(s)
	return s


func _wire(s: Control) -> void:
	s.clicked.connect(_on_click)
	s.hovered.connect(_on_hover)
	s.dropped.connect(_on_drop)


func set_player(p: Node) -> void:
	if player == p:
		return
	player = p
	if p:
		p.inventory_changed.connect(refresh)
	refresh()


## Bag layout shown to the player: stacks first (orbs, potions, materials), then gear.
func bag_entries() -> Array:
	var out: Array = []
	if player == null:
		return out
	var ids: Array = player.inventory.keys()
	ids.sort_custom(func(a, b): return [Items.type_of(a) != "orb", a] < [Items.type_of(b) != "orb", b])
	for id in ids:
		out.append({"stack": str(id), "n": int(player.inventory[id])})
	for inst in player.bag:
		out.append({"inst": inst})
	return out


func refresh() -> void:
	if _bag_slots.is_empty() or player == null:
		return
	for sl in _doll:
		var inst: Dictionary = player.equipment.get(sl, {})
		if inst.is_empty():
			_doll[sl].clear()
		else:
			_doll[sl].set_gear(inst)
	var entries := bag_entries()
	for i in _bag_slots.size():
		var s: Control = _bag_slots[i]
		s.dim = false
		if i < entries.size():
			if entries[i].has("inst"):
				s.set_gear(entries[i]["inst"])
				var base := str(entries[i]["inst"]["base"])
				s.dim = not Items.can_use(base, player.class_id) or player.level < Gear.req_level(entries[i]["inst"])
			else:
				s.set_stack(entries[i]["stack"], entries[i]["n"])
		else:
			s.clear()
	_update_status()
	if _hover and is_instance_valid(_hover):
		_on_hover(_hover, true)


func _update_status() -> void:
	if apply_orb != "":
		_status.text = "Applying %s (%d): click an item. Right-click to cancel." % [Items.display_name(apply_orb), int(player.inventory.get(apply_orb, 0))]
		_status.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	elif vendor_ui and vendor_ui.visible:
		_status.text = "Bag %d/%d. Selling: click an item to select it, then press Sell in the vendor panel." % [player.bag_used(), Items.BAG_SIZE]
	else:
		_status.text = "Bag %d/%d. Click gear = equip, shift = drop, ctrl x2 = destroy. Right-click orb, then item." % [player.bag_used(), Items.BAG_SIZE]
		_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))


func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(player):
		return
	_gold_label.text = "%d gold" % player.gold
	var res: Array = []
	for e in Gear.ELEMENTS:
		res.append("%s %d%%" % [Classes.ELEMENT_INFO[e]["name"], roundi(player.resistance(e))])
	# full element names (2-letter "Fi"/"Me" read as garbage), on two fixed lines so they never wrap mid-entry
	_stats_label.text = "Lv %d  HP %d  MP %d\nAttack %d  Defense %d\nResist: %s\n%s" % [player.level, player.max_hp, player.max_mp,
		player.attack, player.defense, "  ".join(res.slice(0, 3)), "  ".join(res.slice(3))]
	for sl in _doll:
		_doll[sl].highlight = Color(0.5, 1, 0.5, 0.12) if apply_orb == "" and _hover and is_instance_valid(_hover) and not _hover.inst.is_empty() \
			and _hover.kind == "bag" and sl in Items.slots_for(str(_hover.inst["base"])) else Color(0, 0, 0, 0)
		_doll[sl].queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and apply_orb != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		apply_orb = ""
		_update_status()


func _on_hover(s: Control, on: bool) -> void:
	if tooltip == null:
		return
	if not on:
		if _hover == s:
			_hover = null
			tooltip.hide_tip()
		return
	_hover = s
	show_tooltip_for(s)


func show_tooltip_for(s: Control) -> void:
	var at := s.get_global_rect().position + Vector2(s.size.x, 0)
	if not s.inst.is_empty():
		var cmp_slot := ""
		var cmp := {}
		if s.kind != "equip":
			var slots := Items.slots_for(str(s.inst["base"]))
			if not slots.is_empty():
				cmp_slot = slots[0]
				cmp = player.equipment.get(cmp_slot, {})
				if slots.size() > 1 and not player.equipment.get(slots[1], {}).is_empty():
					# rings: compare against the weaker one (the one you'd replace)
					if cmp.is_empty() or Gear.score(player.equipment[slots[1]]) < Gear.score(cmp):
						cmp = {} if cmp.is_empty() else player.equipment[slots[1]]
						cmp_slot = slots[1] if not cmp.is_empty() else slots[0]
		tooltip.show_gear(s.inst, player, at, cmp, cmp_slot)
	elif s.stack_id != "":
		tooltip.show_stack(s.stack_id, s.count, at, vendor_ui != null and vendor_ui.visible)
	else:
		tooltip.hide_tip()


func _on_click(s: Control, button: int, shift: bool, ctrl: bool) -> void:
	if player == null:
		return
	if button == MOUSE_BUTTON_RIGHT:
		if apply_orb != "":
			apply_orb = ""
		elif s.stack_id != "" and Items.type_of(s.stack_id) == "orb":
			apply_orb = s.stack_id
		elif not s.inst.is_empty() and s.kind == "equip":
			player.request_unequip(s.key)
		_update_status()
		return
	if s.kind == "zone":
		return
	if apply_orb != "":
		if not s.inst.is_empty():
			player.request_craft(apply_orb, int(s.inst["uid"]))
			if int(player.inventory.get(apply_orb, 0)) <= 1:
				apply_orb = ""
		_update_status()
		return
	if s.kind == "equip":
		if not s.inst.is_empty():
			if smith and smith.visible:
				smith.select(s.inst)
			else:
				player.request_unequip(s.key)
		return
	if s.stack_id != "" and vendor_ui and vendor_ui.visible:
		vendor_ui.select_stack(s.stack_id)
		return
	if s.stack_id != "":
		match Items.type_of(s.stack_id):
			"consumable":
				player.request_use(s.stack_id)
			"orb":
				apply_orb = s.stack_id
				_update_status()
			_:
				if smith and smith.visible and int(Items.info(s.stack_id).get("sell", 0)) > 0:
					player.request_sell_stack(s.stack_id)
		return
	if s.inst.is_empty():
		return
	var uid := int(s.inst["uid"])
	if shift:
		player.request_drop(uid)
	elif ctrl:
		if _destroy_armed == uid and Time.get_ticks_msec() - _destroy_armed_ms < 2500:
			player.request_destroy(uid)
			_destroy_armed = -1
		else:
			_destroy_armed = uid
			_destroy_armed_ms = Time.get_ticks_msec()
			_status.text = "Ctrl+click again to DESTROY %s" % Gear.display_name(s.inst)
			_status.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	elif vendor_ui and vendor_ui.visible:
		vendor_ui.select_uid(uid)
	elif map_ui and map_ui.visible and map_ui.mode == "device" and Dungeons.is_ticket(s.inst):
		map_ui.select(s.inst)
	elif smith and smith.visible:
		smith.select(s.inst)
	elif Dungeons.is_ticket(s.inst):
		_status.text = "Dungeon Tickets are opened at the Map Device in Sunny Meadow (E)"
	else:
		player.request_equip(uid)


func _on_drop(target: Control, data: Dictionary) -> void:
	if player == null:
		return
	var uid := int(data["uid"])
	match target.kind:
		"equip":
			player.request_equip(uid, target.key)
		"bag":
			if data["from"] == "equip":
				player.request_unequip(str(data["key"]))
			elif data["from"] == "stash":
				player.request_stash("take", uid)
		"zone":
			if target.key == "drop":
				player.request_drop(uid)
			elif target.key == "destroy":
				player.request_destroy(uid)


## Paper-doll silhouette behind the equipment slots.
class DollFigure extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color(0.85, 0.7, 0.35, 0.12)
		draw_circle(Vector2(96, 22), 18, c)
		draw_rect(Rect2(72, 46, 48, 96), c)
		draw_rect(Rect2(48, 50, 20, 70), c)
		draw_rect(Rect2(124, 50, 20, 70), c)
		draw_rect(Rect2(76, 142, 16, 50), c)
		draw_rect(Rect2(100, 142, 16, 50), c)


## Compact mode (bag only, no paper doll): used beside the wide vendor panel so the
## two panels don't overlap. The panel is anchored to the right edge of the screen.
func set_compact(on: bool) -> void:
	if _left == null or _left.visible == not on:
		return
	_left.visible = not on
	offset_left = -386 if on else -572

