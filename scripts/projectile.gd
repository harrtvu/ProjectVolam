extends Node2D
## Arrow / magic bolt / player spell. Spawned by the server with a start position
## and velocity; every peer simulates the straight flight locally, the server alone
## decides hits.
##   team "monster": hits players (monster arrows, Lich bolts)
##   team "player":  hits monsters (Water/Fire basic attacks, Poison Thorn, Ice Shard,
##                   Tidal Wave, Fireball, Inferno) and applies the skill's effects

const LIFETIME := 2.5
const HIT_RADIUS := 14.0

var proj_id := 0
var kind := "arrow"
var velocity := Vector2.ZERO
var damage := 1
var source := "arrow"
var element := ""
var team := "monster"
var owner_player: Node = null   # server, team "player"
var skill: Dictionary = {}       # server, team "player"
var zone: Node = null
var sync_pos := Vector2.ZERO   # only used at spawn (needed for the visibility filter)
var _age := 0.0
var _life := LIFETIME
var _hit := {}


func setup(id: int, pos: Vector2, vel: Vector2, k: String) -> void:
	proj_id = id
	name = "P%d" % id
	position = pos
	sync_pos = pos
	velocity = vel
	kind = k
	z_index = 5
	add_child(NetUtil.make_synchronizer([], ["sync_pos"]))


func setup_player(p: Node, sk: Dictionary) -> void:
	team = "player"
	owner_player = p
	skill = sk
	element = p.element
	_life = float(sk.get("range", 300.0)) / maxf(1.0, velocity.length())


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_age += delta
	queue_redraw()
	if not multiplayer.is_server():
		return
	var foot := position + Vector2(0, 10)
	if _age > _life or zone.map.blocks_sight(foot):
		_end(foot)
		return
	if team == "monster":
		for p in zone.players_root.get_children():
			if not p.dead and p.position.distance_to(foot) <= HIT_RADIUS:
				p.server_take_damage(damage, source, element)
				queue_free()
				return
		return
	if not is_instance_valid(owner_player) or owner_player.is_queued_for_deletion():
		queue_free()
		return
	var r := float(skill.get("hit_radius", HIT_RADIUS + 4.0))
	for m in zone.monsters_root.get_children():
		if not m.alive or _hit.has(m):
			continue
		var mr := r + (12.0 * float(m.def.get("scale", 1.0)) if m.is_boss else 0.0)
		if m.position.distance_to(foot) <= mr:
			_hit[m] = true
			if skill.has("explode"):
				_end(foot)
				return
			owner_player.hit_monster(m, float(skill.get("mult", 1.0)), skill)
			if not skill.get("pierce", false):
				queue_free()
				return


func _end(at: Vector2) -> void:
	if team == "player" and skill.has("explode") and is_instance_valid(owner_player):
		var rad := float(skill["explode"])
		owner_player._main.zone_fx(zone, "burst", at, rad, Classes.color(element), Vector2.ZERO)
		for m in SkillCaster.monsters_in(owner_player, at, rad):
			owner_player.hit_monster(m, float(skill.get("mult", 1.0)), skill)
	queue_free()


func _draw() -> void:
	match kind:
		"bolt":
			draw_circle(Vector2.ZERO, 6.0, Color(0.6, 1.0, 0.6, 0.35))
			draw_circle(Vector2.ZERO, 3.5, Color(0.75, 1.0, 0.7))
		"fire":
			var back := -velocity.normalized()
			for i in 4:
				draw_circle(back * (i * 5.0), 5.0 - i, Color(1.0, 0.5 - i * 0.1, 0.1, 0.8 - i * 0.18))
			draw_circle(Vector2.ZERO, 3.0, Color(1, 0.9, 0.5))
		"ice":
			var d := velocity.normalized() * 7.0
			var o := d.orthogonal() * 0.45
			draw_colored_polygon(PackedVector2Array([d, o, -d, -o]), Color(0.7, 0.9, 1.0))
			draw_circle(Vector2.ZERO, 6.0, Color(0.5, 0.8, 1.0, 0.25))
		"thorn":
			var d := velocity.normalized() * 8.0
			draw_line(-d, d, Color(0.35, 0.8, 0.3), 3.0)
			draw_circle(d, 2.0, Color(0.6, 1.0, 0.4))
		"wave":
			var a := velocity.angle()
			draw_arc(Vector2.ZERO, 26.0, a - 1.1, a + 1.1, 16, Color(0.4, 0.7, 1.0, 0.85), 6.0)
			draw_arc(Vector2.ZERO, 18.0, a - 0.9, a + 0.9, 12, Color(0.85, 0.95, 1.0, 0.7), 3.0)
		_:
			var d := velocity.normalized() * 9.0
			draw_line(-d, d, Color(0.55, 0.38, 0.2), 2.0)
			draw_line(d, d - d.rotated(0.5) * 0.4, Color(0.85, 0.85, 0.9), 2.0)
			draw_line(d, d - d.rotated(-0.5) * 0.4, Color(0.85, 0.85, 0.9), 2.0)
