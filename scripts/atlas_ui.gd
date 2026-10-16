extends PanelContainer
## Atlas panel (M, or the "Atlas" button at the Map Device): the PoE-style Atlas.
##  * Map tab: pannable (drag) / zoomable (wheel) world map of the 31 named dungeon nodes,
##    five elemental regions around the central Ngu Hanh pinnacle. Hover = tooltip,
##    click = select a node and list the tickets you own for it.
##  * Passives tab: the atlas passive tree. Click a glowing node to spend an atlas point,
##    "Reset" (click twice) refunds everything for gold. All changes are server-validated.

var player: Node = null
var tab := "map"
var selected := ""
var force_hover := ""            # screenshots: always show this node's tooltip
var _title: Label
var _points: Label
var _reset: Button
var _tabs: Array = []
var _view: AtlasView
var _side: RichTextLabel
var _confirm_until := 0


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.97)
	sb.border_color = Color(0.85, 0.75, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	_title = Label.new()
	_title.text = "Atlas of the Five Elements"
	_title.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	_title.add_theme_font_size_override("font_size", 18)
	top.add_child(_title)
	for t in [["map", "Atlas Map"], ["tree", "Atlas Passives"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var tid: String = t[0]
		b.pressed.connect(func(): set_tab(tid))
		top.add_child(b)
		_tabs.append([tid, b])
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_points = Label.new()
	_points.add_theme_font_size_override("font_size", 13)
	top.add_child(_points)
	_reset = Button.new()
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.pressed.connect(_on_reset)
	top.add_child(_reset)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	_view = AtlasView.new()
	_view.panel = self
	_view.custom_minimum_size = Vector2(760, 500)
	_view.clip_contents = true
	hb.add_child(_view)
	_side = RichTextLabel.new()
	_side.bbcode_enabled = true
	_side.custom_minimum_size = Vector2(250, 500)
	_side.add_theme_font_size_override("normal_font_size", 11)
	hb.add_child(_side)
	var hint := Label.new()
	hint.text = "Drag to pan, wheel to zoom, Home to recentre.  Map: hover a node for details, click it to see your tickets for it.  Passives: click a glowing node to spend an atlas point.  M / Esc to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.65)
	vb.add_child(hint)
	set_tab("map")


func set_tab(t: String) -> void:
	tab = t
	for e in _tabs:
		e[1].button_pressed = e[0] == t
	if _view:
		_view.recentre()
	refresh()


func set_player(p: Node) -> void:
	if player != p:
		player = p
		if p and not p.inventory_changed.is_connected(refresh):
			p.inventory_changed.connect(refresh)
	refresh()


func _on_reset() -> void:
	if not is_instance_valid(player):
		return
	if Time.get_ticks_msec() > _confirm_until:
		_confirm_until = Time.get_ticks_msec() + 3000
		return
	_confirm_until = 0
	player.request_dungeon("atlas_respec")


## Tickets in the bag (and stash) that open this node.
func tickets_for(nid: String) -> Array:
	var out: Array = []
	if player == null:
		return out
	for src in [player.bag, player.stash]:
		for inst in src:
			if typeof(inst) == TYPE_DICTIONARY and Dungeons.is_ticket(inst) and inst.get("rarity") != "unique" and Atlas.node_of_ticket(inst) == nid:
				out.append(inst)
	return out


func select_node(nid: String) -> void:
	selected = nid
	refresh()


func node_tooltip(nid: String) -> Array:
	var n := Atlas.node(nid)
	var a: Dictionary = player.atlas if player else {}
	var st := Atlas.state(a, nid)
	var col := Classes.color(n["theme"]) if not n.get("pinnacle", false) else Color(1, 0.85, 0.4)
	var out: Array = [[str(n["name"]), col.lerp(Color.WHITE, 0.35)]]
	var kind: String = "Pinnacle - the Five Elements" if n.get("pinnacle", false) else ("Guardian of the %s region" % Classes.ELEMENT_INFO[n["theme"]]["name"] if n.get("guardian", false) else "%s region" % Classes.ELEMENT_INFO[n["theme"]]["name"])
	out.append(["%s  -  Tier %d  -  monster level %d" % [Dungeons.theme_name(n["theme"]), n["tier"], Dungeons.level(int(n["tier"]))], Color(0.85, 0.85, 0.9)])
	out.append([kind, Color(0.7, 0.75, 0.85)])
	var stc := {"completed": Color(0.5, 1, 0.5), "available": Color(1, 0.9, 0.4), "locked": Color(0.6, 0.6, 0.65)}
	var runs := int(a.get("done", {}).get(nid, 0))
	out.append([{"completed": "Completed (%d run%s)" % [runs, "" if runs == 1 else "s"], "available": "Available - you can run this node",
		"locked": "Locked - complete an adjacent node" if not n.get("pinnacle", false) else "Locked - defeat all five Guardians (%d/5)" % Atlas.guardians_done(a)}[st], stc[st]])
	var bdone: bool = a.get("bonus", {}).has(nid)
	out.append(["Bonus objective: %s  %s" % [Atlas.bonus_text(nid), "[DONE]" if bdone else ""], Color(1, 0.75, 0.3) if bdone else Color(0.9, 0.8, 0.6)])
	out.append(["Atlas points: first completion %s, bonus %s" % ["earned" if runs > 0 else "+1", "earned" if bdone else "+1"], Color(0.7, 0.85, 1.0)])
	var adj: Array = []
	for x in Atlas.adjacent(nid):
		adj.append(str(Atlas.node(x)["name"]))
	out.append(["Paths to: " + ", ".join(adj), Color(0.6, 0.6, 0.7)])
	out.append(["Tickets owned for this node: %d" % tickets_for(nid).size(), Color(0.85, 0.75, 0.4)])
	return out


func passive_tooltip(pid: String) -> Array:
	var pd: Dictionary = Atlas.passives()[pid]
	var a: Dictionary = player.atlas if player else {}
	var out: Array = [[str(pd["name"]), Color(1, 0.85, 0.45) if pd["kind"] == "notable" else Color(0.9, 0.9, 0.95)]]
	if pid == "a_root":
		out.append(["The heart of your Atlas: every path starts here.", Color(0.7, 0.7, 0.75)])
		return out
	for line in Atlas.fx_text(pd["fx"]).split("\n"):
		out.append([line, Color(0.55, 0.75, 1.0)])
	if a.get("passives", []).has(pid):
		out.append(["Allocated", Color(0.5, 1, 0.5)])
	else:
		var why := Atlas.can_allocate(a, pid)
		out.append(["Click to allocate (1 atlas point)" if why == "" else why, Color(1, 0.9, 0.4) if why == "" else Color(0.7, 0.6, 0.6)])
	return out


func refresh() -> void:
	if _side == null or player == null:
		return
	var a: Dictionary = player.atlas
	_points.text = "Atlas points: %d free  (%d earned, %d spent)   Gold: %d" % [Atlas.points_free(a), Atlas.points_earned(a), Atlas.points_spent(a), player.gold]
	if Time.get_ticks_msec() < _confirm_until:
		_reset.text = "Click again: reset for %d gold" % Atlas.respec_cost(a)
	else:
		_reset.text = "Reset passives (%d gold)" % Atlas.respec_cost(a)
	_reset.visible = tab == "tree"
	var L: Array = []
	if tab == "map":
		var done: int = a.get("done", {}).size()
		L.append("[b][color=#ffe08a]Atlas Map[/color][/b]")
		L.append("Completed nodes: [color=#9fff9f]%d / %d[/color]   Bonus: [color=#ffbf4d]%d[/color]" % [done, Atlas.nodes().size(), a.get("bonus", {}).size()])
		L.append("Guardians defeated: %d / 5" % Atlas.guardians_done(a))
		L.append("Dungeon item quantity from completions: +%d%%" % roundi(Dungeons.atlas_iiq(a)))
		L.append("[color=#8a8a99]Bright = available, ✓ = completed, gold ring = bonus done, dark = locked.[/color]")
		if not a.get("migrated", []).is_empty():
			L.append("[color=#8a8a99]Migrated from the old atlas: %s[/color]" % ", ".join(a["migrated"]))
		L.append("")
		if selected != "" and Atlas.has_node(selected):
			var n := Atlas.node(selected)
			L.append("[b]%s[/b]  (T%d, %s)" % [n["name"], n["tier"], Atlas.state(a, selected)])
			var tk := tickets_for(selected)
			if tk.is_empty():
				L.append("[color=#aaaaaa]You own no tickets for this node.%s[/color]" % (" Buy one at the Ticket Merchant." if Atlas.merchant_sells(a, n["theme"], int(n["tier"])) else ""))
			else:
				L.append("Your tickets for it (open at the Map Device):")
				for t in tk:
					L.append("  • " + Gear.summary(t).replace("[", "[lb]"))
		else:
			L.append("[color=#aaaaaa]Click a node to see your tickets for it.[/color]")
	else:
		L.append("[b][color=#ffe08a]Atlas Passives[/color][/b]")
		L.append("Earn points by completing nodes for the first time and by bonus objectives.")
		var fx := Atlas.effects(a)
		if fx.is_empty():
			L.append("[color=#aaaaaa]No passives allocated.[/color]")
		else:
			L.append("[color=#8fc0ff]%s[/color]" % Atlas.fx_text(fx))
	_side.text = "\n".join(L)
	_view.queue_redraw()


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() % 500 < 20:
		refresh()


# ======================================================================== the graph view

class AtlasView extends Control:
	var panel: Node
	var offset := Vector2.ZERO
	var zoom := 0.4
	var _drag := false
	var _moved := 0.0
	var hover := ""

	func recentre() -> void:
		offset = Vector2.ZERO
		zoom = 0.37 if panel == null or panel.tab == "map" else 0.62
		queue_redraw()

	func _to_screen(p: Vector2) -> Vector2:
		return size * 0.5 + (p + offset) * zoom

	func _items() -> Dictionary:
		return Atlas.nodes() if panel.tab == "map" else Atlas.passives()

	func _pick(pos: Vector2) -> String:
		var best := ""
		var bd := 22.0
		var it := _items()
		for k in it:
			var d := _to_screen(it[k]["pos"]).distance_to(pos)
			if d < bd:
				bd = d
				best = k
		return best

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
				zoom = minf(2.5, zoom * 1.12)
				queue_redraw()
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
				zoom = maxf(0.35, zoom / 1.12)
				queue_redraw()
			elif e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					_drag = true
					_moved = 0.0
				else:
					_drag = false
					if _moved < 6.0:
						var k := _pick(e.position)
						if k != "":
							if panel.tab == "map":
								panel.select_node(k)
							elif is_instance_valid(panel.player):
								panel.player.request_dungeon("atlas_alloc", {"id": k})
			accept_event()
		elif e is InputEventMouseMotion:
			if _drag:
				offset += e.relative / zoom
				_moved += e.relative.length()
			hover = _pick(e.position)
			queue_redraw()
		elif e is InputEventKey and e.pressed and e.keycode == KEY_HOME:
			recentre()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.06))
		if panel == null or panel.player == null:
			return
		var a: Dictionary = panel.player.atlas
		var font := get_theme_default_font()
		if panel.tab == "map":
			_draw_map(a, font)
		else:
			_draw_tree(a, font)
		var h: String = panel.force_hover if panel.force_hover != "" else hover
		if h != "" and _items().has(h):
			var lines: Array = panel.node_tooltip(h) if panel.tab == "map" else panel.passive_tooltip(h)
			_draw_tip(_to_screen(_items()[h]["pos"]) + Vector2(18, 10), lines, font)

	func _draw_map(a: Dictionary, font: Font) -> void:
		# region wedges + central pentagon
		for k in Dungeons.ORDER.size():
			var th: String = Dungeons.ORDER[k]
			var ang := deg_to_rad(-90.0 + 72.0 * k)
			var pts := PackedVector2Array([_to_screen(Vector2.ZERO)])
			for s in 9:
				var aa := ang - deg_to_rad(36) + deg_to_rad(72) * s / 8.0
				pts.append(_to_screen(Vector2(cos(aa), sin(aa)) * 640.0))
			draw_colored_polygon(pts, Classes.color(th).darkened(0.82))
			var lp := _to_screen(Vector2(cos(ang), sin(ang)) * 650.0)
			var label := "%s - %s" % [Classes.ELEMENT_INFO[th]["name"], Dungeons.theme_name(th)]
			draw_string(font, lp - Vector2(60, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 120, int(13 * clampf(zoom, 0.8, 1.4)), Classes.color(th).lerp(Color.WHITE, 0.3))
		var pent := PackedVector2Array()
		for k in 6:
			var aa := deg_to_rad(-90.0 + 72.0 * k)
			pent.append(_to_screen(Vector2(cos(aa), sin(aa)) * 140.0))
		draw_polyline(pent, Color(1, 0.85, 0.4, 0.35), 2.0)
		var N := Atlas.nodes()
		for k in N:
			for b in N[k]["adj"]:
				if str(k) < str(b):
					var lit: bool = Atlas.is_done(a, k) or Atlas.is_done(a, b)
					draw_line(_to_screen(N[k]["pos"]), _to_screen(N[b]["pos"]), Color(0.85, 0.75, 0.5, 0.7) if lit else Color(0.4, 0.4, 0.5, 0.35), 2.5 if lit else 1.5)
		for k in N:
			var n: Dictionary = N[k]
			var p := _to_screen(n["pos"])
			var st := Atlas.state(a, k)
			var col: Color = Classes.color(n["theme"]) if not n.get("pinnacle", false) else Color(1, 0.85, 0.4)
			var r := (7.0 + int(n["tier"]) * 0.5) * clampf(zoom * 1.6, 0.8, 2.0)
			if n.get("guardian", false) or n.get("pinnacle", false):
				r *= 1.35
			var fill := col if st == "completed" else (col.darkened(0.35) if st == "available" else col.darkened(0.8))
			if st == "available":
				draw_circle(p, r + 5, Color(1, 1, 0.7, 0.18 + 0.12 * sin(Time.get_ticks_msec() / 300.0)))
			draw_circle(p, r, fill)
			draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.8) if st != "locked" else Color(0.4, 0.4, 0.45), 2.0)
			if a.get("bonus", {}).has(k):
				draw_arc(p, r + 4, 0, TAU, 32, Color(1, 0.8, 0.2), 2.5)
			if st == "completed":
				draw_string(font, p - Vector2(6, -5), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r), Color(0.05, 0.1, 0.05))
			if k == panel.selected:
				draw_arc(p, r + 8, 0, TAU, 32, Color(0.6, 0.9, 1.0), 2.0)
			var tag: String = "T%d" % n["tier"]
			draw_string(font, p + Vector2(-30, r + 13), tag, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(0.9, 0.9, 0.9) if st != "locked" else Color(0.5, 0.5, 0.55))
			if zoom >= 0.7 or n.get("guardian", false) or n.get("pinnacle", false) or k == panel.selected:
				draw_string(font, p + Vector2(-70, r + 25), str(n["name"]), HORIZONTAL_ALIGNMENT_CENTER, 140, 10, Color(0.8, 0.8, 0.85, 0.9 if st != "locked" else 0.5))

	func _draw_tree(a: Dictionary, font: Font) -> void:
		var P := Atlas.passives()
		var alloc: Array = a.get("passives", [])
		for k in P:
			for b in P[k]["adj"]:
				if str(k) < str(b):
					var on: bool = (alloc.has(k) or k == "a_root") and (alloc.has(b) or b == "a_root")
					draw_line(_to_screen(P[k]["pos"]), _to_screen(P[b]["pos"]), Color(1, 0.85, 0.4, 0.9) if on else Color(0.4, 0.4, 0.5, 0.45), 3.0 if on else 1.5)
		for k in P:
			var pd: Dictionary = P[k]
			var p := _to_screen(pd["pos"])
			var r := (14.0 if pd["kind"] == "notable" else (17.0 if pd["kind"] == "root" else 9.0)) * clampf(zoom * 1.3, 0.7, 1.8)
			var on: bool = alloc.has(k) or k == "a_root"
			var can: bool = not on and Atlas.can_allocate(a, k) == ""
			var reach: bool = not on and Atlas.can_allocate(a, k).contains("no atlas points")
			var el := str(k).get_slice("_", 1)
			var col: Color = Classes.color(el) if Classes.ELEMENT_INFO.has(el) else Color(0.85, 0.8, 0.6)
			if can:
				draw_circle(p, r + 5, Color(1, 1, 0.6, 0.25))
			draw_circle(p, r, col if on else (col.darkened(0.45) if can or reach else col.darkened(0.8)))
			draw_arc(p, r, 0, TAU, 28, Color(1, 0.85, 0.4) if on else Color(0.5, 0.5, 0.55), 2.0)
			if pd["kind"] == "notable" or pd["kind"] == "root":
				draw_string(font, p + Vector2(-70, r + 13), str(pd["name"]), HORIZONTAL_ALIGNMENT_CENTER, 140, 10, Color(0.9, 0.85, 0.7))

	func _draw_tip(at: Vector2, lines: Array, font: Font) -> void:
		var w := 0.0
		for l in lines:
			w = maxf(w, font.get_string_size(str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		var h := 18.0 * lines.size() + 10.0
		var box := Rect2(at, Vector2(w + 20, h))
		if box.end.x > size.x:
			box.position.x = size.x - box.size.x - 4
		if box.end.y > size.y:
			box.position.y = size.y - box.size.y - 4
		draw_rect(box, Color(0.02, 0.02, 0.04, 0.95))
		draw_rect(box, Color(0.85, 0.75, 0.45), false, 1.5)
		for i in lines.size():
			draw_string(font, box.position + Vector2(10, 20 + 18 * i), str(lines[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if i == 0 else 12, lines[i][1])
