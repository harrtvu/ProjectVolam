extends Control
## The Wu Xing diagram: generating cycle around the outside, overcoming star inside.

var highlight := ""
const ORDER := ["wood", "fire", "earth", "metal", "water"]   # generating order, clockwise


func _ready() -> void:
	custom_minimum_size = Vector2(250, 250)


func _node_pos(i: int) -> Vector2:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.36
	return c + Vector2.from_angle(-PI / 2.0 + TAU * i / 5.0) * r


func _arrow(a: Vector2, b: Vector2, col: Color, w: float, dashed := false) -> void:
	var dir := a.direction_to(b)
	var s := a + dir * 24.0
	var e := b - dir * 24.0
	if dashed:
		draw_dashed_line(s, e, col, w, 6.0)
	else:
		draw_line(s, e, col, w)
	draw_colored_polygon(PackedVector2Array([e + dir * 4.0, e - dir * 8.0 + dir.orthogonal() * 6.0,
		e - dir * 8.0 - dir.orthogonal() * 6.0]), col)


func _draw() -> void:
	var font := get_theme_default_font()
	# generating (outer pentagon), overcoming (inner star)
	for i in 5:
		_arrow(_node_pos(i), _node_pos((i + 1) % 5), Color(0.55, 0.9, 0.55, 0.9), 2.0)
	for i in 5:
		var e: String = ORDER[i]
		var target: String = Classes.OVERCOMES[e]
		var col := Color(1.0, 0.45, 0.4, 0.9) if e == highlight or target == highlight else Color(1.0, 0.45, 0.4, 0.45)
		_arrow(_node_pos(i), _node_pos(ORDER.find(target)), col, 2.0, true)
	for i in 5:
		var e: String = ORDER[i]
		var p := _node_pos(i)
		var c := Classes.color(e)
		if e == highlight:
			draw_circle(p, 25.0, Color(1, 1, 1, 0.9))
		draw_texture_rect(Classes.element_icon(e, true), Rect2(p - Vector2(21, 21), Vector2(42, 42)), false)
		var label := "%s %s" % [Classes.ELEMENT_INFO[e]["viet"], Classes.ELEMENT_INFO[e]["name"]]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var ly := p.y + 36.0 if p.y > size.y * 0.4 else p.y - 26.0
		draw_string_outline(font, Vector2(p.x - w / 2.0, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color.BLACK)
		draw_string(font, Vector2(p.x - w / 2.0, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c.lerp(Color.WHITE, 0.3))
