extends Control
## One square in the bag grid / paper doll / stash / blacksmith. Draws the icon with a
## rarity-coloured frame, stack count and "+N" upgrade level; supports click and drag & drop.
## The owning panel connects `clicked(slot, button, shift, ctrl)`, `hovered(slot, on)` and
## `dropped(target_slot, data)`.

signal clicked(slot: Control, button: int, shift: bool, ctrl: bool)
signal hovered(slot: Control, on: bool)
signal dropped(target: Control, data: Dictionary)

var kind := "bag"            # bag | equip | stash | smith | zone
var key := ""                # equip slot name, stack id, or zone name ("drop"/"destroy")
var inst: Dictionary = {}    # gear instance shown (if any)
var stack_id := ""           # stackable item id shown (if any)
var count := 0
var placeholder := ""        # paper-doll caption when empty
var highlight := Color(0, 0, 0, 0)
var dim := false


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_gear(i: Dictionary) -> void:
	inst = i
	stack_id = ""
	count = 0
	queue_redraw()


func set_stack(id: String, n: int) -> void:
	inst = {}
	stack_id = id
	count = n
	queue_redraw()


func clear() -> void:
	inst = {}
	stack_id = ""
	count = 0
	queue_redraw()


func is_empty() -> bool:
	return inst.is_empty() and stack_id == ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		clicked.emit(self, event.button_index, event.shift_pressed, event.ctrl_pressed)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		hovered.emit(self, true)
	elif what == NOTIFICATION_MOUSE_EXIT:
		hovered.emit(self, false)


func _get_drag_data(_at: Vector2) -> Variant:
	if inst.is_empty() or kind == "zone" or kind == "market" or kind == "listing":
		return null
	var prev := TextureRect.new()
	prev.texture = Items.icon(str(inst["base"]))
	prev.size = Vector2(32, 32)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(prev)
	return {"from": kind, "key": key, "uid": int(inst["uid"]), "inst": inst}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("uid"):
		return false
	match kind:
		"equip":
			return data["from"] == "bag" and key in Items.slots_for(str(data["inst"]["base"]))
		"bag":
			return data["from"] == "equip" or data["from"] == "stash"
		"zone", "smith":
			return data["from"] == "bag" or (kind == "smith" and data["from"] == "equip")
		"stash", "market":
			return data["from"] == "bag"
	return false


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(self, data)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := Color(0.35, 0.32, 0.28)
	if not inst.is_empty():
		col = Gear.RARITY_COLOR.get(str(inst.get("rarity", "normal")), col)
	elif stack_id != "" and Items.type_of(stack_id) == "orb":
		col = Color(0.6, 0.85, 1.0)
	draw_rect(r, Color(0.05, 0.05, 0.07, 0.9))
	if not inst.is_empty() and inst.get("rarity", "normal") != "normal":
		draw_rect(r.grow(-2), Color(col, 0.13))
	if highlight.a > 0.0:
		draw_rect(r.grow(-1), highlight)
	draw_rect(r, col if not is_empty() else Color(0.3, 0.28, 0.25), false, 2.0 if not is_empty() else 1.0)
	var tex: Texture2D = null
	if not inst.is_empty():
		tex = Items.icon(str(inst["base"]))
	elif stack_id != "":
		tex = Items.icon(stack_id)
	var font := get_theme_default_font()
	if tex:
		var s := minf(size.x, size.y) - 8.0
		draw_texture_rect(tex, Rect2((size - Vector2(s, s)) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, 0.45) if dim else Color.WHITE)
	elif placeholder != "":
		draw_string(font, Vector2(0, size.y / 2.0 + 4), placeholder, HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, Color(1, 1, 1, 0.35))
	if count > 1:
		draw_string_outline(font, Vector2(2, size.y - 3), str(count), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 11, 3, Color.BLACK)
		draw_string(font, Vector2(2, size.y - 3), str(count), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 11, Color.WHITE)
	if not inst.is_empty() and int(inst.get("upg", 0)) > 0:
		var t := "+%d" % int(inst["upg"])
		draw_string_outline(font, Vector2(3, 12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(font, Vector2(3, 12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 1.0, 0.6))
	if kind == "zone":
		draw_string(font, Vector2(0, size.y / 2.0 + 4), placeholder, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(1, 0.75, 0.6))
