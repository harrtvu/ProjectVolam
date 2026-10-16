extends Node2D
## Short-lived skill visual effect (client side only; purely cosmetic).
## Spawned by Main.fx() when the server tells peers in a zone that a skill fired.

var kind := "ring"
var radius := 60.0
var color := Color.WHITE
var extra := Vector2.ZERO     # "line": end point, "telegraph": (delay, 0)
var _t := 0.0
var _life := 0.45
var _dots: Array = []


func setup(k: String, pos: Vector2, r: float, c: Color, e: Vector2) -> void:
	kind = k
	position = pos
	radius = r
	color = c
	extra = e
	z_index = 4
	match kind:
		"telegraph":
			_life = maxf(0.2, e.x)
		"heal", "rain":
			_life = 0.9
		"burst", "roots":
			_life = 0.6
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 18:
		_dots.append([Vector2.from_angle(rng.randf() * TAU), rng.randf_range(0.4, 1.0), rng.randf_range(2.0, 4.5)])


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / _life
	var c := color
	match kind:
		"ring":
			var r := radius * (0.3 + 0.7 * k)
			draw_circle(Vector2.ZERO, r, Color(c, 0.18 * (1.0 - k)))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(c.lerp(Color.WHITE, 0.3), 1.0 - k), 4.0)
			for d in _dots:
				draw_circle(d[0] * r * d[1], d[2] * (1.0 - k), Color(c.lerp(Color.WHITE, 0.4), 1.0 - k))
		"burst":
			draw_circle(Vector2.ZERO, radius * (0.5 + 0.5 * k), Color(c, 0.35 * (1.0 - k)))
			for d in _dots:
				draw_circle(d[0] * radius * k * d[1] * 1.2, d[2] * 1.4 * (1.0 - k), Color(c.lerp(Color(1, 0.9, 0.5), 0.5), 1.0 - k))
		"roots":
			draw_circle(Vector2.ZERO, radius, Color(c, 0.2 * (1.0 - k)))
			for d in _dots:
				var tip: Vector2 = d[0] * radius * d[1]
				draw_line(tip * 0.2, tip * (0.2 + 0.8 * minf(1.0, k * 2.0)), Color(0.45, 0.3, 0.15, 1.0 - k), 3.0)
				draw_circle(tip, 2.5, Color(c, 1.0 - k))
		"line":
			draw_line(Vector2.ZERO, extra - position, Color(c.lerp(Color.WHITE, 0.5), 1.0 - k), radius * 0.5 * (1.0 - k) + 2.0)
		"slash":
			var a := float(get_instance_id() % 628) / 100.0
			draw_arc(Vector2(0, -10), radius, a, a + 2.2, 12, Color(c.lerp(Color.WHITE, 0.6), 1.0 - k), 3.0)
		"heal":
			for d in _dots.slice(0, 6):
				var p: Vector2 = Vector2(d[0].x * radius * 0.6, -10.0 - k * 30.0 * d[1])
				draw_line(p - Vector2(3, 0), p + Vector2(3, 0), Color(0.4, 1.0, 0.5, 1.0 - k), 2.0)
				draw_line(p - Vector2(0, 3), p + Vector2(0, 3), Color(0.4, 1.0, 0.5, 1.0 - k), 2.0)
		"rain":
			draw_circle(Vector2.ZERO, radius, Color(c, 0.12 * (1.0 - k)))
			for d in _dots:
				var p: Vector2 = d[0] * radius * d[1]
				var y := fmod(k * 3.0 + d[1], 1.0) * 30.0
				draw_line(p + Vector2(0, y - 30.0), p + Vector2(0, y - 22.0), Color(0.6, 0.85, 1.0, 1.0 - k), 2.0)
		"telegraph":
			draw_circle(Vector2.ZERO, radius * k, Color(c, 0.25))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(c, 0.9), 2.0)
