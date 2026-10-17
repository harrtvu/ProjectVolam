class_name ArtTest
## ART STYLE TEST (branch art-test only): Ninja Adventure (pixel-boy, CC0) reskin of Whisperwood Forest +
## shared dark wuxia mood pass. Off by default; enable with --art-test (or env VOLAM_ART_TEST=1).
## Assets are built by tools/build_art_test.py into res://assets/art_test/. See CREDITS.md.

const DIR := "res://assets/art_test/"
static var enabled := false
static var mood := true          # --art-test-nomood: reskin without the darkening pass
static var _cache := {}
static var _vfx_meta := {}

static func init_from_args() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	enabled = args.has("--art-test") or OS.get_environment("VOLAM_ART_TEST") == "1"
	mood = not args.has("--art-test-nomood")


static func tex(file: String) -> Texture2D:
	if not enabled:
		return null
	if not _cache.has(file):
		_cache[file] = load(DIR + file) if ResourceLoader.exists(DIR + file) else null
	return _cache[file]


## 4x7 sheet column for a facing: 0 down, 1 up, 2 left, 3 right.
static func dir_col(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return 2 if v.x < 0.0 else 3
	return 1 if v.y < 0.0 else 0


static func vfx_meta() -> Dictionary:
	if _vfx_meta.is_empty() and FileAccess.file_exists(DIR + "vfx.json"):
		_vfx_meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "vfx.json"))
	return _vfx_meta


## Element whose colour is closest to `c` (fx only carry a colour).
static func element_of(c: Color) -> String:
	var best := "metal"
	var bd := 99.0
	for e in ["metal", "wood", "water", "fire", "earth"]:
		var ec := Classes.color(e)
		var d := Vector3(ec.r - c.r, ec.g - c.g, ec.b - c.b).length()
		if d < bd:
			bd = d
			best = e
	return best


## Soft radial light texture for PointLight2D.
static func light_tex() -> Texture2D:
	if _cache.has("_light"):
		return _cache["_light"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 256
	t.height = 256
	_cache["_light"] = t
	return t


static func make_light(color: Color, energy: float, scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = light_tex()
	l.color = color
	l.energy = energy
	l.texture_scale = scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	return l


const GRADE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float desat = 0.35;
uniform float contrast = 1.12;
uniform vec3 shadow_tint = vec3(0.80, 0.92, 1.05);
uniform vec3 high_tint = vec3(1.08, 0.98, 0.86);
uniform float vignette = 0.55;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat);
	c = (c - 0.5) * contrast + 0.5;
	c *= mix(shadow_tint, high_tint, smoothstep(0.15, 0.75, l));
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * smoothstep(0.25, 0.75, length(d * vec2(1.25, 1.0)));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

## The shared mood pass: CanvasModulate on the world + a colour-grade layer under the HUD.
static func add_mood(main: Node) -> void:
	if not enabled or not mood:
		return
	var cm := CanvasModulate.new()
	cm.name = "ArtTestMood"
	cm.color = Color(0.50, 0.50, 0.62)
	main.add_child(cm)
	var layer := CanvasLayer.new()
	layer.name = "ArtTestGrade"
	layer.layer = 1   # above the world, below the UI (moved to layer 2 when the art test is on)
	main.add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRADE_SHADER
	mat.shader = sh
	rect.material = mat
	layer.add_child(rect)
