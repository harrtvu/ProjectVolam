extends Node2D
## An item lying in the world. Spawned by the server's LootSpawner so every
## client sees it; the server alone decides who picks it up.
## Gear pickups carry their full instance (rarity, affixes) in the spawn data, so
## every client can show a rarity-coloured name label (and a light beam for rares/uniques).

const LIFETIME := 60.0
const GEAR_LIFETIME := 120.0
const AUTO_PICKUP_RADIUS := 20.0

var loot_id: int = 0
var item_id: String = "gold"
var amount: int = 1
var inst: Dictionary = {}
var _age := 0.0
var _sprite: Sprite2D
var _label: Label
var zone: Node = null
var _rarity := ""
var _flash := 0.0

static var _chime: AudioStreamWAV


func setup(id: int, item: String, count: int, pos: Vector2, instance: Dictionary = {}) -> void:
	loot_id = id
	item_id = item
	amount = count
	inst = instance
	name = "Loot%d" % id
	position = pos
	# (synchronizer only exists so the zone visibility filter can apply to it)
	add_child(NetUtil.make_synchronizer([], ["amount"]))
	_sprite = Sprite2D.new()
	_sprite.texture = Items.icon(item)
	_sprite.scale = Vector2(0.75, 0.75)
	add_child(_sprite)
	var text := ""
	var col := Color.WHITE
	if not inst.is_empty():
		_rarity = str(inst.get("rarity", "normal"))
		text = Gear.display_name(inst)
		col = Gear.RARITY_COLOR.get(_rarity, Color.WHITE)
	elif Items.type_of(item) == "orb":
		text = Items.display_name(item) + (" x%d" % count if count > 1 else "")
		col = Color(0.75, 0.95, 1.0)
	elif count > 1:
		text = str(count)
	if text != "":
		_label = Label.new()
		_label.text = text
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size = Vector2(220, 16)
		_label.position = Vector2(-110, -30)
		_label.z_index = 20
		_label.add_theme_font_size_override("font_size", 10)
		_label.add_theme_color_override("font_color", col)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
		add_child(_label)
	if _rarity == "rare" or _rarity == "unique":
		_flash = 1.0
		z_index = 1


func label_text() -> String:
	return Gear.summary(inst) if not inst.is_empty() else "%d x %s" % [amount, item_id]


func _ready() -> void:
	if (_rarity == "rare" or _rarity == "unique") and DisplayServer.get_name() != "headless":
		var p := AudioStreamPlayer2D.new()
		p.stream = _get_chime()
		p.volume_db = -6.0 if _rarity == "unique" else -10.0
		p.pitch_scale = 1.25 if _rarity == "unique" else 1.0
		add_child(p)
		p.play()


## A short procedurally generated "ding" (no audio files needed).
static func _get_chime() -> AudioStreamWAV:
	if _chime:
		return _chime
	var rate := 22050
	var n := int(rate * 0.45)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 7.0)
		var v := (sin(TAU * 1318.5 * t) * 0.6 + sin(TAU * 1975.5 * t) * 0.4) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 20000.0))
	_chime = AudioStreamWAV.new()
	_chime.format = AudioStreamWAV.FORMAT_16_BITS
	_chime.mix_rate = rate
	_chime.data = data
	return _chime


func _process(delta: float) -> void:
	_age += delta
	_flash = maxf(0.0, _flash - delta * 0.8)
	_sprite.position.y = -4.0 + sin(_age * 4.0 + loot_id) * 2.0
	var life := GEAR_LIFETIME if not inst.is_empty() else LIFETIME
	if multiplayer.is_server() and _age > life:
		queue_free()  # despawns on all clients via the spawner
	if _age > life - 5.0:
		visible = int(_age * 8.0) % 2 == 0  # blink before vanishing
	if _rarity != "":
		queue_redraw()


func _draw() -> void:
	if _rarity == "rare" or _rarity == "unique" or _rarity == "magic":
		var c: Color = Gear.RARITY_COLOR[_rarity]
		var h := 90.0 if _rarity != "magic" else 40.0
		var pulse := 0.6 + 0.4 * sin(_age * 3.0)
		for i in 6:   # a soft vertical beam of light
			var w := 7.0 - i
			draw_rect(Rect2(-w / 2.0, -h, w, h), Color(c, 0.05 * pulse + 0.02 * i))
		if _flash > 0.0:
			draw_circle(Vector2.ZERO, 40.0 * (1.2 - _flash), Color(c, 0.5 * _flash))
		draw_arc(Vector2(0, 2), 11.0, 0, TAU, 20, Color(c, 0.8), 1.5)
	draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.25))
