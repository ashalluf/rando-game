extends RefCounted
## The water review (WaterReview; shaders ocean.gdshader, ocean_closeup.gdshaderinc, surf.gdshaderinc,
## beach_sand.gdshader) for tests/smoke_test.gd. Loaded at run time (not named there). Reads shader
## sources and plain data; sets the A/B global and puts it back, so it does not care what ran before
## it or leave anything for what runs after.
##
## Checks: the shader's sea floor (oc_seabed) is SeaSurface.seabed() number for number and point for
## point (change one, change both); the foam is surf_foam() everywhere the old polka-dot net and
## spaghetti web were, with the old code kept behind the switch; the shallows are close-up only and
## refract through the coarse ripple; the swash caustics add light (never multiply the sand's grains);
## the wheel's hub in the night mirror is the pier park's wheel; the ocean still samples no texture;
## WATER_REVIEW=0 turns the global off.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var ocean := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	var oc := FileAccess.get_file_as_string("res://shaders/ocean_closeup.gdshaderinc")
	var surf := FileAccess.get_file_as_string("res://shaders/surf.gdshaderinc")
	var sand := FileAccess.get_file_as_string("res://shaders/beach_sand.gdshader")

	# The sea floor: the shader's constants are the sand's rows and SeaSurface's.
	var want := {"OC_BED_TOP": SeaSurface.MESH_Y, "OC_BED_STEEP_AT": CityChunk.SAND_STEEP_AT,
		"OC_BED_STEEP_Y": CityChunk.SAND_STEEP_Y, "OC_BED_WET": CityChunk.SAND_WET, "OC_BED_LOW": CityChunk.SAND_LOW,
		"OC_BED_SHELF": 0.09}
	var consts := {}
	var bad: Array[String] = []
	for k: String in want:
		var v := _const(oc, k)
		consts[k] = v
		if is_nan(v) or absf(v - float(want[k])) > 1e-4:
			bad.append("%s %.3f/%.3f" % [k, v, float(want[k])])
	_t._check(bad.is_empty(), "water review: the shader's sea floor is the sand's rows and SeaSurface's (%s)" % ", ".join(bad))
	var worst := 0.0
	for s: float in [0.0, 1.0, 3.4, 3.6, 10.0, 25.9, 26.1, 60.0, 200.0]:
		worst = maxf(worst, absf(_seabed(consts, s) - SeaSurface.seabed(s)))
	_t._check(worst < 1e-3, "water review: oc_seabed() follows SeaSurface.seabed() along the profile (worst %.4f m)" % worst)
	_t._check(SeaSurface.seabed(30.0) < SeaSurface.seabed(5.0) and SeaSurface.seabed(5.0) < SeaSurface.MESH_Y,
		"water review: the floor falls away offshore, under the water plane")

	# The foam: surf_foam() in the bores, the old lace, the open water's lace and the swash, with the
	# old patterns only behind the switch.
	_t._check(surf.contains("float surf_foam(") and surf.contains("float surf_caustic(") and surf.contains("global uniform float water_review;"),
		"water review: surf.gdshaderinc holds the shared foam, caustics and the switch")
	_t._check(ocean.count("surf_foam(") >= 3 and sand.contains("surf_foam("),
		"water review: the bores, the old lace, the open water's lace and the swash wear surf_foam (%d in the ocean)" % ocean.count("surf_foam("))
	_t._check(ocean.contains("bool wrv = water_review > 0.5;") and ocean.contains("} else if (rich && near_c > 0.001 && dist < 45.0") and sand.contains("bool wrv = water_review > 0.5;"),
		"water review: the old net and web are kept behind WATER_REVIEW=0")
	# Clear shallows: close-up only, gated by the switch, refracted through the coarse ripple.
	_t._check(ocean.contains("if (water_review > 0.5 && rich && near_c > 0.001 && dist < shallows_reach") and ocean.contains("refract(view_dir, normalize(world_normal + vec3(-grad_lens.x"),
		"water review: the shallows are seen through only close to, through the coarse ripple")
	# Caustics add light at the sand's mean colour (multiplied, every bright grain sparkled in rows).
	_t._check(sand.contains("alb += cs_as_uniform(caustic_tone) * caustic_gain") and oc.contains("c += floor_color * (caustic_gain"),
		"water review: the caustics add light, they never multiply the sand's texture")
	_t._check(surf.contains("float soft = max(soft0, 2.5 * px / cs);"), "water review: a caustic line is never drawn under a few pixels")
	# Derivatives only outside branches (llvmpipe hands back 0 inside).
	var fl := oc.substr(oc.find("vec3 oc_sea_floor("), 2500)
	_t._check(not fl.contains("fwidth") and not fl.contains("dFdx"), "water review: the sea floor takes its pixel size from the caller")
	# No texture in the ocean (the web's sampler budget).
	_t._check(ocean.count("sampler2D") + oc.count("sampler2D") + surf.count("sampler2D") == 0, "water review: the ocean still samples no texture")

	# The wheel in the night mirror is the pier park's wheel.
	var hub := OceanCloseup.wheel_hub()
	var at := Vector2.ZERO
	for lm: Dictionary in Landmarks.all():
		if str(lm.id) == "pier":
			at = lm.anchor
	var want_hub := Vector4(at.x + PierPark.WHEEL_AT.x, PierPark.DECK_TOP + FerrisWheel.HUB_H, at.y + PierPark.WHEEL_AT.y, FerrisWheel.RADIUS)
	_t._check(at != Vector2.ZERO and hub.is_equal_approx(want_hub), "water review: the mirrored wheel is the pier park's (%s)" % str(hub))
	var mat := PropFactory.ocean_material()
	OceanCloseup.apply(mat)
	var got: Variant = mat.get_shader_parameter("pier_wheel")
	_t._check(got is Vector4 and (got as Vector4).is_equal_approx(hub), "water review: the ocean material carries the wheel")
	_t._check(ocean.contains("oc_wheel_mirror(wp3, refl, smear, TIME)"), "water review: the night mirror draws the wheel")

	# The A/B.
	var gl := FileAccess.get_file_as_string("res://project.godot")
	_t._check(gl.contains("water_review={"), "water review: the water_review shader global is declared")
	var old := OS.get_environment("WATER_REVIEW")
	OS.set_environment("WATER_REVIEW", "0")
	var off := WaterReview.enabled()
	WaterReview.apply()
	var off_raw: Variant = RenderingServer.global_shader_parameter_get("water_review")
	OS.set_environment("WATER_REVIEW", old)
	WaterReview.apply()
	var on_raw: Variant = RenderingServer.global_shader_parameter_get("water_review")
	# The dummy renderer (headless) keeps no globals: it hands back null.
	var off_v := float(off_raw) if off_raw != null else 0.0
	var on_v := float(on_raw) if on_raw != null else (1.0 if old != "0" else 0.0)
	_t._check(not off and is_zero_approx(off_v) and is_equal_approx(on_v, 1.0 if old != "0" else 0.0),
		"water review: WATER_REVIEW=0 turns the global off (%.1f / %.1f)" % [off_v, on_v])


## A `const float NAME = v;` from shader source (NAN if missing).
static func _const(src: String, name: String) -> float:
	var i := src.find("const float %s = " % name)
	if i < 0:
		return NAN
	var a := i + ("const float %s = " % name).length()
	return src.substr(a, src.find(";", a) - a).to_float()


## ocean_closeup.gdshaderinc oc_seabed() in GDScript, from the shader's own numbers.
static func _seabed(c: Dictionary, s: float) -> float:
	if s < c.OC_BED_STEEP_AT:
		return lerpf(c.OC_BED_TOP, c.OC_BED_STEEP_Y, clampf(s / c.OC_BED_STEEP_AT, 0.0, 1.0))
	if s < c.OC_BED_WET:
		return lerpf(c.OC_BED_STEEP_Y, c.OC_BED_LOW, (s - c.OC_BED_STEEP_AT) / (c.OC_BED_WET - c.OC_BED_STEEP_AT))
	return maxf(c.OC_BED_LOW - (s - c.OC_BED_WET) * c.OC_BED_SHELF, -13.0)
