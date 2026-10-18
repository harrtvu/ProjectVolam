extends Control
## In-game menu (Esc): Resume, Hideout, Settings, Controls, Return to Main Menu, Quit Game.
## Runs with PROCESS_MODE_ALWAYS so it keeps working while the tree is paused.
## Solo host (listen server, nobody else connected) -> the world really pauses
## (get_tree().paused); otherwise the game continues online and only local input stops.
## Settings live in user://settings.cfg (client side).

signal closed

const CONTROLS := [
	["W A S D / Arrows", "Move"], ["Space", "Basic attack"], ["1 2 3 4 (hold = aim ground skills)", "Skills"],
	["Left-click", "Select target (empty ground clears it)"], ["Right-click", "Select monster and attack"],
	["Tab", "Cycle nearest enemies"], ["E", "Pick up / blacksmith / Map Device / merchant / vendor"],
	["Q", "Drink a health potion"], ["I", "Inventory"], ["C", "Character sheet"], ["T", "Passive web"],
	["N", "Zone map"], ["M", "Atlas"], ["P", "Party panel"], ["H", "Hideout panel / decoration mode (in your hideout)"], ["Enter", "Chat (Esc cancels)"], ["Esc", "Close the topmost panel, else this menu"],
	["/invite NAME", "Chat: invite a player to your party (or the target frame's button)"], ["/accept  /decline", "Chat: answer a party invite"],
	["/party", "Chat: list your party"], ["/leave", "Chat: leave your party"], ["/kick NAME", "Chat: remove a member (leader)"], ["/p TEXT", "Chat: party chat"], ["/hideout", "Chat: go to your hideout"],
]

static var settings_path := "user://settings.cfg"
static var master_volume := 1.0
static var fullscreen := false
static var show_damage_numbers := true
static var returned_to_menu := false   # survives the scene reload of "Return to Main Menu"

var main: Node
var paused_world := false
var _pages := {}
var _note: Label
var _vol: HSlider
var _fs: CheckButton
var _dmg: CheckButton


static func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(settings_path) == OK:
		master_volume = clampf(float(cf.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
		fullscreen = bool(cf.get_value("video", "fullscreen", false))
		show_damage_numbers = bool(cf.get_value("game", "show_damage_numbers", true))
	apply_settings()


static func save_settings() -> int:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("game", "show_damage_numbers", show_damage_numbers)
	return cf.save(settings_path)


static func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	NetUtil.show_popups = show_damage_numbers
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fit()
	get_viewport().size_changed.connect(_fit)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.97)
	sb.border_color = Color(0.85, 0.75, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(380, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	var title := Label.new()
	title.text = "Project Volam"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	vb.add_child(title)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 12)
	vb.add_child(_note)
	# main page
	var mp := VBoxContainer.new()
	mp.add_theme_constant_override("separation", 6)
	for b in [["Resume", close_menu], ["Hideout", _go_hideout], ["Settings", func(): _show("settings")], ["Controls / Help", func(): _show("controls")],
			["Return to Main Menu", func(): _leave(true)], ["Quit Game", func(): _leave(false)]]:
		mp.add_child(_btn(b[0], b[1]))
	vb.add_child(mp)
	_pages["main"] = mp
	# settings page
	var sp := VBoxContainer.new()
	sp.add_theme_constant_override("separation", 6)
	var vl := Label.new()
	vl.text = "Master volume"
	sp.add_child(vl)
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 1.0
	_vol.step = 0.05
	_vol.value_changed.connect(func(v): master_volume = v; apply_settings(); save_settings())
	sp.add_child(_vol)
	_fs = CheckButton.new()
	_fs.text = "Fullscreen"
	_fs.toggled.connect(func(on): fullscreen = on; apply_settings(); save_settings())
	sp.add_child(_fs)
	_dmg = CheckButton.new()
	_dmg.text = "Show damage numbers / floating text"
	_dmg.toggled.connect(func(on): show_damage_numbers = on; apply_settings(); save_settings())
	sp.add_child(_dmg)
	var kb := Label.new()
	kb.text = "Key bindings are listed under Controls / Help (read-only)."
	kb.add_theme_font_size_override("font_size", 11)
	kb.modulate = Color(1, 1, 1, 0.7)
	sp.add_child(kb)
	sp.add_child(_btn("Back", func(): _show("main")))
	vb.add_child(sp)
	_pages["settings"] = sp
	# controls page
	var cp := VBoxContainer.new()
	var gc := GridContainer.new()
	gc.columns = 2
	gc.add_theme_constant_override("h_separation", 16)
	for c in CONTROLS:
		for i in 2:
			var l := Label.new()
			l.text = c[i]
			l.add_theme_font_size_override("font_size", 12)
			if i == 0:
				l.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
			gc.add_child(l)
	cp.add_child(gc)
	cp.add_child(_btn("Back", func(): _show("main")))
	vb.add_child(cp)
	_pages["controls"] = cp
	visible = false


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS   # fires on mouse-down: a click that drifts off the button still counts
	b.pressed.connect(cb)
	return b


func _show(page: String) -> void:
	for k in _pages:
		_pages[k].visible = k == page
	if page == "settings":
		_vol.set_value_no_signal(master_volume)
		_fs.set_pressed_no_signal(fullscreen)
		_dmg.set_pressed_no_signal(show_damage_numbers)


## Solo host: listen server (not dedicated) with no remote peers.
func is_solo_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not main.is_dedicated \
		and multiplayer.get_peers().is_empty()


func open_menu() -> void:
	if visible:
		return
	visible = true
	_show("main")
	paused_world = is_solo_host()
	if paused_world:
		get_tree().paused = true
		_note.text = "Game paused"
	else:
		_note.text = "Game continues online - your input is stopped"
	main._log("menu opened (%s)" % ("solo host: world paused" if paused_world else "online: game continues, input stopped"))


func close_menu() -> void:
	if not visible:
		return
	visible = false
	if paused_world:
		get_tree().paused = false
		paused_world = false
	main._log("menu closed (world running: %s)" % (not get_tree().paused))
	closed.emit()


func toggle() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


## Someone connected to our listen server while paused: the world must run for them.
func on_peer_joined() -> void:
	if paused_world:
		get_tree().paused = false
		paused_world = false
		_note.text = "A player joined - game continues online"
		main._log("menu: a player joined, world unpaused")


func _leave(to_menu: bool) -> void:
	main._log("menu: %s" % ("return to main menu" if to_menu else "quit game"))
	visible = false
	paused_world = false
	if not to_menu:
		get_tree().paused = false
	main.leave_game(to_menu)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not _pages["main"].visible:
			_show("main")
		else:
			close_menu()
		get_viewport().set_input_as_handled()


# ================================================================ --menu-test driver (runs while paused too)

var _tt := 0.0
var _tstep := 0
var _tpos := {}
var _tsyncs := 0   # monster sync packets received while the menu is open (menu test)


func _count_sync() -> void:
	_tsyncs += 1


## Menu test: count server updates for the tracked monsters (idle monsters may not move for 4s).
func _watch_syncs(on: bool) -> void:
	var me: Node = main._local_player()
	if me == null or me.zone == null:
		return
	for m in me.zone.monsters_root.get_children():
		var sy := m.get_node_or_null("Sync") as MultiplayerSynchronizer
		if sy == null:
			continue
		if on and not sy.synchronized.is_connected(_count_sync):
			sy.synchronized.connect(_count_sync)
		elif not on and sy.synchronized.is_connected(_count_sync):
			sy.synchronized.disconnect(_count_sync)


func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	get_viewport().push_input(up)


func _monster_snapshot() -> Dictionary:
	var out := {}
	var me: Node = main._local_player()
	if me == null or me.zone == null:
		return out
	for m in me.zone.monsters_root.get_children():
		out[m.name] = m.position
	return out


func _moved(before: Dictionary) -> float:
	var now := _monster_snapshot()
	var d := 0.0
	for k in before:
		if now.has(k):
			d += (now[k] as Vector2).distance_to(before[k])
	return d


func _process(delta: float) -> void:
	if main == null or not main.menu_test or main._shutting_down or not main.in_game or main._local_player() == null:
		return
	_tt += delta
	var at := [6.0, 7.0, 8.0, 9.0, 13.0, 14.0, 18.0, 19.0, 20.0]
	if _tstep >= at.size() or _tt < at[_tstep]:
		return
	match _tstep:
		0:
			_key(KEY_I)          # open the inventory ...
		1:
			main._log("menu test: inventory open %s, menu open %s" % [main.inventory_ui.visible, visible])
			_key(KEY_ESCAPE)     # ... Esc closes the panel, not the menu
		2:
			main._log("menu test: after Esc: inventory open %s, menu open %s" % [main.inventory_ui.visible, visible])
			_key(KEY_ESCAPE)     # nothing open -> menu
		3:
			_tpos = _monster_snapshot()
			_tsyncs = 0
			_watch_syncs(true)
			main._log("menu test: menu open %s, tree paused %s, solo host %s, %d monsters tracked, peer connected %s" % [visible, get_tree().paused,
				is_solo_host(), _tpos.size(), multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED])
		4:
			_watch_syncs(false)
			main._log("menu test: while the menu was open for 4s, monsters moved %.1f px in total, %d server updates (tree paused %s); local input dir %s" % [_moved(_tpos),
				_tsyncs, get_tree().paused, main._local_player()._last_sent])
			_key(KEY_ESCAPE)     # Esc again closes the menu
		5:
			_tpos = _monster_snapshot()
			main._log("menu test: menu open %s, tree paused %s, peer connected %s" % [visible, get_tree().paused,
				multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED])
		6:
			main._log("menu test: after resuming, monsters moved %.1f px in 4s" % _moved(_tpos))
			if main.menu_test_leave != "":
				open_menu()
		7:
			if main.menu_test_leave != "":
				_leave(main.menu_test_leave == "menu")
	_tstep += 1


## "Hideout": ask the server to take us to our hideout (it refuses from inside a dungeon).
func _go_hideout() -> void:
	close_menu()
	var me: Node = main._local_player() if main else null
	if me:
		main._log("[menu] Hideout pressed")
		me.request_hideout("enter")
