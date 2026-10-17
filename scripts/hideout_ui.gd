extends PanelContainer
## Hideout panel: opened by the Hideout Master in Sunny Meadow (E) or with H in
## your hideout. Shop (buy decorations with gold), your decoration inventory
## (pick one to place), themes, and the Decoration Mode toggle.
## Decoration mode (in your hideout): left click = place the selected decoration,
## or pick up the one under the cursor and click again to move it; right click =
## remove; R = rotate, F = flip the one under the cursor. Click a station and then
## a free cell to move the station. Everything is a request the server validates.

var player: Node = null
var main: Node = null
var deco_mode := false
var selected := ""        # catalog id to place
var moving := -1          # decoration index being moved
var moving_station := ""
var _title: Label
var _status: Label
var _gold: Label
var _shop: VBoxContainer
var _owned: VBoxContainer
var _themes: HBoxContainer
var _mode_btn: Button
var _enter_btn: Button


func _ready() -> void:
	custom_minimum_size = Vector2(430, 0)
	var v := VBoxContainer.new()
	add_child(v)
	_title = Label.new()
	_title.text = "Hideout"
	_title.add_theme_font_size_override("font_size", 18)
	v.add_child(_title)
	_gold = Label.new()
	v.add_child(_gold)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	_enter_btn = Button.new()
	_enter_btn.text = "Enter Hideout"
	_enter_btn.pressed.connect(func(): if player: player.request_hideout("enter"))
	hb.add_child(_enter_btn)
	_mode_btn = Button.new()
	_mode_btn.text = "Decoration Mode (H)"
	_mode_btn.pressed.connect(toggle_mode)
	hb.add_child(_mode_btn)
	var l := Label.new()
	l.text = "Theme"
	v.add_child(l)
	_themes = HBoxContainer.new()
	v.add_child(_themes)
	var cols := HBoxContainer.new()
	v.add_child(cols)
	for k in [["Shop (gold)", "_shop"], ["Your decorations", "_owned"]]:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(205, 300)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := Label.new()
		h.text = k[0]
		col.add_child(h)
		sc.add_child(col)
		cols.add_child(sc)
		set(k[1], col)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(410, 0)
	v.add_child(_status)


func set_player(p: Node, m: Node) -> void:
	player = p
	main = m


func in_hideout() -> bool:
	return player != null and player.zone != null and player.zone.has_method("is_hideout") and player.zone.is_hideout()


class DecoGrid extends Node2D:
	## Decoration-mode overlay: the placement grid, the door lane / station keep-outs and the cursor cell.
	var layout: Dictionary = {}
	var cursor := Vector2i(-1, -1)

	func _process(_d: float) -> void:
		var pos := get_local_mouse_position()
		var c := Vector2i(floori(pos.x / Zones.TILE), floori(pos.y / Zones.TILE))
		if c != cursor:
			cursor = c
			queue_redraw()

	func _draw() -> void:
		var T := float(Zones.TILE)
		var r := Hideouts.ROOM
		for x in range(r.position.x, r.end.x + 1):
			draw_line(Vector2(x * T, r.position.y * T), Vector2(x * T, r.end.y * T), Color(1, 1, 1, 0.12), 1.0)
		for y in range(r.position.y, r.end.y + 1):
			draw_line(Vector2(r.position.x * T, y * T), Vector2(r.end.x * T, y * T), Color(1, 1, 1, 0.12), 1.0)
		var dl := Hideouts.DOOR_LANE
		draw_rect(Rect2(Vector2(dl.position) * T, Vector2(dl.size) * T), Color(1, 0.3, 0.2, 0.18))
		for s in layout.get("stations", {}):
			var sc := Hideouts.cell_of(layout["stations"][s])
			draw_rect(Rect2(Vector2(sc - Vector2i.ONE) * T, Vector2(3, 3) * T), Color(1, 0.8, 0.2, 0.15))
		if r.has_point(cursor):
			var ok := Hideouts.blocked_reason(layout, cursor) == ""
			draw_rect(Rect2(Vector2(cursor) * T, Vector2(T, T)), Color(0.3, 1, 0.4, 0.35) if ok else Color(1, 0.2, 0.2, 0.35))


var _grid: DecoGrid = null


func _update_grid() -> void:
	var want := deco_mode and in_hideout()
	if _grid and (not want or not is_instance_valid(_grid) or _grid.get_parent() != player.zone):
		if is_instance_valid(_grid):
			_grid.queue_free()
		_grid = null
	if want and _grid == null:
		_grid = DecoGrid.new()
		_grid.z_index = 5
		player.zone.add_child(_grid)
	if _grid:
		_grid.layout = player.hideout
		_grid.queue_redraw()


func toggle_mode() -> void:
	deco_mode = not deco_mode and in_hideout()
	moving = -1
	moving_station = ""
	if main:
		main._log("[hideout] decoration mode %s" % ("ON" if deco_mode else "off"))
	refresh()


func _clear(c: Container, keep := 1) -> void:
	for i in range(c.get_child_count() - 1, keep - 1, -1):
		var n := c.get_child(i)
		c.remove_child(n)
		n.queue_free()


func refresh() -> void:
	if player == null or not is_inside_tree():
		return
	var h: Dictionary = player.hideout
	if not in_hideout():
		deco_mode = false
	_update_grid()
	_title.text = "%s - %s" % ["Your Hideout" if in_hideout() else "Hideout Master", Hideouts.THEMES[h["theme"]]["name"]]
	_gold.text = "Gold: %d    Placed %d / %d decorations" % [player.gold, h["decor"].size(), Hideouts.MAX_DECOR]
	_enter_btn.disabled = in_hideout()
	_mode_btn.disabled = not in_hideout()
	_mode_btn.text = "Decoration Mode: ON (H)" if deco_mode else "Decoration Mode (H)"
	_clear(_themes, 0)
	for t in Hideouts.THEME_ORDER:
		var b := Button.new()
		b.text = Hideouts.THEMES[t]["name"].get_slice(" ", 0)
		b.tooltip_text = Hideouts.THEMES[t]["name"] + ("" if h["unlocked"].has(t) else " (locked: defeat its Atlas Guardian)")
		b.disabled = not h["unlocked"].has(t) or not in_hideout()
		b.toggle_mode = true
		b.button_pressed = h["theme"] == t
		b.pressed.connect(func(): player.request_hideout("theme", {"id": t}))
		_themes.add_child(b)
	_clear(_shop)
	for id in Hideouts.CATALOG:
		var c: Dictionary = Hideouts.CATALOG[id]
		var b := Button.new()
		b.text = "%s  -  %dg" % [c["name"], int(c["price"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = player.gold < int(c["price"])
		b.pressed.connect(func(): player.request_hideout("buy", {"id": id}))
		_shop.add_child(b)
	_clear(_owned)
	for id in h["owned"]:
		var n := int(h["owned"][id])
		var placed := Hideouts.placed_count(h, id)
		var b := Button.new()
		b.text = "%s%s  %d/%d placed" % ["> " if selected == id else "", Hideouts.CATALOG[id]["name"], placed, n]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = placed >= n
		b.pressed.connect(func():
			selected = id
			if in_hideout() and not deco_mode:
				toggle_mode()
			refresh())
		_owned.add_child(b)
	if deco_mode:
		_status.text = "Decoration mode: %s. Left click = place / pick up & move, right click = remove, R = rotate, F = flip. Click a station, then a cell, to move it." % (
			("moving decoration #%d" % moving) if moving >= 0 else ("moving the " + Hideouts.STATION_NAMES[moving_station]) if moving_station != "" else
			("placing " + Hideouts.CATALOG[selected]["name"]) if selected != "" else "select one of your decorations")
	elif in_hideout():
		_status.text = "Press H (or the button) for decoration mode. The door at the bottom leads back to Sunny Meadow."
	else:
		_status.text = "Buy decorations here, then decorate your hideout (Enter Hideout, /hideout, or Esc > Hideout)."


func _cell_under_mouse() -> Vector2i:
	var pos: Vector2 = main._cursor_zone_pos(player)
	return Vector2i(floori(pos.x / Zones.TILE), floori(pos.y / Zones.TILE))


func _decor_at(c: Vector2i) -> int:
	var dec: Array = player.hideout["decor"]
	for i in dec.size():
		if int(dec[i]["x"]) == c.x and int(dec[i]["y"]) == c.y:
			return i
	return -1


func _station_at(c: Vector2i) -> String:
	for s in Hideouts.STATIONS:
		var sc := Hideouts.cell_of(player.hideout["stations"][s])
		if absi(sc.x - c.x) <= 1 and absi(sc.y - c.y) <= 1:
			return s
	return ""


## Decoration mode mouse / keys (called by Main before its own input handling). True = consumed.
func handle_world_input(event: InputEvent) -> bool:
	if not deco_mode or player == null:
		return false
	if not in_hideout():
		deco_mode = false
		return false
	if event is InputEventMouseButton and event.pressed:
		click(_cell_under_mouse(), event.button_index == MOUSE_BUTTON_RIGHT)
		return true
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_R or event.keycode == KEY_F):
		var i := _decor_at(_cell_under_mouse())
		if i >= 0:
			player.request_hideout("rotate" if event.keycode == KEY_R else "flip", {"index": i})
		return true
	return false


## One decoration-mode click at a cell (also used by the test bot).
func click(c: Vector2i, right := false) -> void:
	if right:
		var r := _decor_at(c)
		if r >= 0:
			player.request_hideout("remove", {"index": r})
		moving = -1
		moving_station = ""
	elif moving_station != "":
		player.request_hideout("station", {"station": moving_station, "x": c.x, "y": c.y})
		moving_station = ""
	elif moving >= 0:
		player.request_hideout("move", {"index": moving, "x": c.x, "y": c.y})
		moving = -1
	elif _decor_at(c) >= 0:
		moving = _decor_at(c)
	elif _station_at(c) != "":
		moving_station = _station_at(c)
	elif selected != "":
		player.request_hideout("place", {"id": selected, "x": c.x, "y": c.y})
	refresh()
