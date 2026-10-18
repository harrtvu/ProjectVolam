extends PanelContainer
## First-time tutorial for a new character (shown once; the server saves the flag).
## Five steps, each finished by doing it: move, use a skill (1-4), pick up loot (E),
## equip it (I), open the passive web (T). "Skip tutorial" ends it at any time.

signal finished(skipped: bool)

const STEPS := [
	["Move", "Walk around with  W A S D  (or the arrow keys)."],
	["Skills", "Use a skill with the keys  1 2 3 4  (the bar at the bottom). Skills target the monster you clicked, else the cursor."],
	["Loot", "A helmet dropped next to you. Walk onto it and press  E  to pick it up."],
	["Equip gear", "Press  I  to open your bag and click the helmet to equip it."],
	["Passive web", "Press  T  to open the passive web. You get 1 point per level - spend them on connected nodes."],
]

var main: Node
var step := 0
var _title: Label
var _text: Label
var _start_pos := Vector2.INF
var _baseline := ""
var _skill_used := false


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	sb.border_color = Color(1.0, 0.85, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(440, 0)
	var vb := VBoxContainer.new()
	add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(420, 0)
	vb.add_child(_text)
	var skip := Button.new()
	skip.text = "Skip tutorial"
	skip.focus_mode = Control.FOCUS_NONE
	skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	skip.pressed.connect(skip_tutorial)
	vb.add_child(skip)


func begin() -> void:
	step = 0
	visible = true
	_enter_step()


func _enter_step() -> void:
	var me: Node = main._local_player()
	_title.text = "Tutorial  %d/%d  -  %s" % [step + 1, STEPS.size(), STEPS[step][0]]
	_text.text = STEPS[step][1]
	_start_pos = me.position if me else Vector2.INF
	_baseline = _state(me)
	_skill_used = false
	main._log("tutorial step %d/%d: %s" % [step + 1, STEPS.size(), STEPS[step][0]])
	if step == 2 and me:
		me.request_tutorial("loot")


## Called by the player when a skill key is used.
func on_skill() -> void:
	_skill_used = true


func _state(me: Node) -> String:
	if me == null:
		return ""
	if step == 2:
		return str(me.bag.size())
	if step == 3:
		return me.equip_summary()
	return ""


func _process(_delta: float) -> void:
	if not visible or main == null:
		return
	var me: Node = main._local_player()
	if me == null:
		return
	if _start_pos == Vector2.INF:
		_start_pos = me.position
	_place()
	if step == 0:   # show how far along the Move step is
		var pct := clampi(roundi(me.position.distance_to(_start_pos) / 120.0 * 100.0), 0, 100)
		_text.text = "%s\nProgress: %d%%" % [STEPS[0][1], pct]
	var done := false
	match step:
		0: done = me.position.distance_to(_start_pos) > 120.0
		1: done = _skill_used
		2: done = me.bag.size() > int(_baseline)
		3: done = me.equip_summary() != _baseline
		4: done = main.talent_ui.visible
	if done:
		main._log("tutorial step %d done: %s" % [step + 1, STEPS[step][0]])
		step += 1
		if step >= STEPS.size():
			_finish(false)
		else:
			_enter_step()


## Dock the box where it covers none of the open windows (the step may have just asked
## for one, e.g. the inventory): top-centre, else left under the stats, else bottom-right, else above the skill bar.
func _place() -> void:
	var vp := get_viewport_rect().size
	var cands := [Vector2((vp.x - size.x) / 2.0, 64.0), Vector2(10.0, 176.0), Vector2(vp.x - size.x - 10.0, vp.y - 80.0 - size.y), Vector2((vp.x - size.x) / 2.0, vp.y - 80.0 - size.y)]
	var busy: Array = []
	for w in main._big_windows() + [main.minimap]:
		if w.visible and (w != main.minimap or main.minimap.big):
			busy.append(w.get_global_rect())
	for c in cands:
		var r := Rect2(c, size)
		var ok := true
		for b in busy:
			if r.intersects(b):
				ok = false
		if ok:
			position = c
			return
	position = cands[3]


## For the UI self-test: does the box overlap any open big window?
func covers_a_window() -> bool:
	var r := get_global_rect()
	for w in main._big_windows():
		if w.visible and r.intersects(w.get_global_rect()):
			return true
	return false


func skip_tutorial() -> void:
	main._log("tutorial skipped at step %d/%d" % [step + 1, STEPS.size()])
	_finish(true)


func _finish(skipped: bool) -> void:
	visible = false
	var me: Node = main._local_player()
	if me:
		me.request_tutorial("skip" if skipped else "done")
	if not skipped:
		main.show_banner("Tutorial complete", "Good luck out there!")
	finished.emit(skipped)
