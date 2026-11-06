class_name Rc5TowerGondola
extends RefCounted
## The window washers seen from a neighbour's roof (wave 8 refcam `tower_gondola` in
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "The window washers from the roof next door").
## What TowerGondolas / GondolaRig draw at 20-60 m, where the old look fell apart:
##   - the wire ropes and lanyards: 5 mm cylinders were under a pixel past ~10 m, so the cradle
##     hung on nothing - now `shaders/gondola_rope.gdshader`, never thinner than a pixel, its real
##     width as coverage (`rope_material()`);
##   - the water on the glass (gondola_streaks.gdshader `look`): a dark film at 16 % over dark
##     glass was invisible - now the wet glass mirrors the sky in sheets and runs, the soap is a
##     white lather the squeegee cuts through, the drips catch the light;
##   - (more in the HANDOFF section.)
## RC5_GONDOLA=0 in the environment is the A/B: every piece exactly as before.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_GONDOLA") != "0"

static var _rope_mats: Dictionary = {}


## The rope / lanyard material: the min-pixel rope shader in `color` (sRGB as written).
static func rope_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _rope_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/gondola_rope.gdshader")
		m.set_shader_parameter("rope_color", color)
		# Galvanised wire: metal; the lanyard's polyester: dull.
		m.set_shader_parameter("metal", 0.6 if color.s < 0.2 else 0.0)
		m.set_shader_parameter("rough", 0.45 if color.s < 0.2 else 0.8)
		_rope_mats[key] = m
	return _rope_mats[key]
