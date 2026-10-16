extends HBoxContainer
## HUD skill bar: 4 slots with icon, hotkey, mana cost, cooldown sweep, lock state.

var player: Node
var _slots: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		var s := Slot.new()
		s.index = i
		s.bar = self
		add_child(s)
		_slots.append(s)


func _process(_delta: float) -> void:
	for s in _slots:
		s.queue_redraw()
		if is_instance_valid(player):
			var sid := Classes.skill_id(player.class_id, s.index)
			var sk: Dictionary = player.skill_def(sid)
			s.tooltip_text = "[%d] %s\n%s\nMana %d  Cooldown %.1fs  Unlocks at level %d%s" % [s.index + 1, sk["name"], sk["desc"],
				sk["cost"], sk["cd"], Classes.UNLOCK_LEVELS[s.index],
				"\nHold the key to aim at the ground, release to cast" if player.is_ground_skill(s.index) else ""]


class Slot extends Control:
	var index := 0
	var bar: Node

	func _init() -> void:
		custom_minimum_size = Vector2(52, 52)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _set_hover(index))
		mouse_exited.connect(func(): _set_hover(-1))

	func _set_hover(i: int) -> void:
		var m := get_node_or_null("/root/Main")
		if m:
			m.hover_slot = i

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_instance_valid(bar.player):
				bar.player.request_skill(index)
			accept_event()

	func _draw() -> void:
		var p = bar.player
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.6))
		if not is_instance_valid(p):
			return
		var sid := Classes.skill_id(p.class_id, index)
		var sk: Dictionary = p.skill_def(sid)
		draw_texture_rect(Classes.skill_icon(sid), Rect2(2, 2, size.x - 4, size.y - 4), false)
		var font := get_theme_default_font()
		var locked: bool = p.level < Classes.UNLOCK_LEVELS[index]
		var left: float = p.cooldown_left(index)
		if locked:
			draw_rect(r, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(6, 32), "Lv %d" % Classes.UNLOCK_LEVELS[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
		elif left > 0.0:
			# cooldown sweep: dark pie shrinking clockwise
			var frac: float = clampf(left / maxf(0.01, p.cooldown_total(index)), 0.0, 1.0)
			var c := size / 2.0
			draw_rect(r, Color(0, 0, 0, 0.25))
			if frac > 0.02:
				# pie as a fan of triangles (never degenerate)
				var steps := maxi(2, ceili(32.0 * frac))
				var rad := size.x * 0.5 - 2.0
				for i in steps:
					var a0 := -PI / 2.0 + TAU * frac * float(i) / steps
					var a1 := -PI / 2.0 + TAU * frac * float(i + 1) / steps
					draw_primitive(PackedVector2Array([c, c + Vector2.from_angle(a0) * rad, c + Vector2.from_angle(a1) * rad]),
						PackedColorArray([Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6)]), PackedVector2Array())
			draw_string_outline(font, Vector2(14, 33), "%.1f" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
			draw_string(font, Vector2(14, 33), "%.1f" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		elif p.mp < int(sk["cost"]):
			draw_rect(r, Color(0.1, 0.2, 0.6, 0.45))
		draw_rect(r, Classes.color(p.element) if not locked else Color(0.4, 0.4, 0.4), false, 2.0)
		draw_string_outline(font, Vector2(4, 14), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
		draw_string(font, Vector2(4, 14), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.7))
		var cost := str(sk["cost"])
		draw_string_outline(font, Vector2(size.x - 6 - cost.length() * 7, size.y - 4), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color.BLACK)
		draw_string(font, Vector2(size.x - 6 - cost.length() * 7, size.y - 4), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0))
