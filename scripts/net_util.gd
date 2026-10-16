class_name NetUtil
## Small helpers shared by networked entities.


## Builds a MultiplayerSynchronizer for `props`.
## `always` props are sent every network tick (unreliable, good for positions);
## the rest are sent only when they change (reliable, good for HP / flags).
static func make_synchronizer(always: Array, on_change: Array) -> MultiplayerSynchronizer:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for p in always + on_change:
		var np := NodePath(".:" + str(p))
		cfg.add_property(np)
		cfg.property_set_spawn(np, true)
		if p in always:
			cfg.property_set_replication_mode(np, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		else:
			cfg.property_set_replication_mode(np, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = cfg
	return sync


## Moves a client-side replica smoothly toward the last position from the server.
static func smooth_follow(node: Node2D, target: Vector2, delta: float) -> void:
	if node.position.distance_to(target) > 96.0:
		node.position = target
	else:
		node.position = node.position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))


## Floating combat text ("-4", "+15", "LEVEL UP!") that rises and fades.
## Client: the locally selected target (monster or player node), or null.
## Untyped on purpose: it may hold a freed node until Main notices.
static var selected = null
static var show_popups := true    # Settings: "show damage numbers / floating text"


static func is_selected(n: Object) -> bool:
	return selected != null and is_instance_valid(selected) and selected == n


static func draw_select_ring(ci: CanvasItem, radius: float, col: Color) -> void:
	var t := Time.get_ticks_msec() * 0.004
	ci.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
	ci.draw_circle(Vector2.ZERO, radius, Color(col, 0.18))
	ci.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, col, 3.0)
	for i in 4:
		var a := t + i * TAU / 4.0
		ci.draw_arc(Vector2.ZERO, radius + 5.0, a, a + 0.5, 6, Color(col, 0.8), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func popup(parent: Node2D, text: String, color: Color, y := -40.0) -> void:
	if DisplayServer.get_name() == "headless" or not parent.is_inside_tree() or not show_popups:
		return
	var l := Label.new()
	l.text = text
	l.z_index = 20
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 16)
	l.position = Vector2(-60, y)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	# Deferred: this can be triggered from a synced property setter while the
	# parent is still being set up by the MultiplayerSpawner.
	l.ready.connect(func():
		var tw := l.create_tween()
		tw.set_parallel(true)
		tw.tween_property(l, "position:y", y - 24.0, 0.8)
		tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
		tw.chain().tween_callback(l.queue_free))
	parent.add_child.call_deferred(l)
