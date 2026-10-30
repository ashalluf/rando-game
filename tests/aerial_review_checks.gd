extends RefCounted
## The aerial review (AerialReview, docs/HANDOFF.md "The aerial review"): checks for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. No shader runs
## headless: the fixes are held by the shaders' sources (the copies that must agree), the
## uniforms the city set on its materials, and the far canopy's colours.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_t._check(AerialReview.enabled, "aerial review: on in the smoke test (AERIAL_REVIEW=0 is the A/B only)")
	_sea_copies()
	_materials(city)
	_mottle_near_untouched()
	_canopy_gain()


## The sea's two shaders agree: the plane paints its water on the ocean chunks' own hand-over
## window, and the ocean's copy of the plane's layered haze has the plane's numbers.
func _sea_copies() -> void:
	var ocean := _source("res://shaders/ocean.gdshader")
	var ground := _source("res://shaders/macro_ground.gdshader")
	var relief := _source("res://shaders/macro_relief.gdshaderinc")
	var pairs := [
		[ocean, "handover_start", ground, "sea_paint_start"],
		[ocean, "handover_end", ground, "sea_paint_end"],
		[ocean, "far_pixel_angle", ground, "pixel_angle"],
		[ocean, "far_swell", ground, "sea_swell"],
	]
	for n in ["range_haze", "range_haze_from", "range_haze_reach", "range_haze_top", "range_haze_keep"]:
		pairs.append([ocean, n, relief, n])
	var bad: Array = []
	for p: Array in pairs:
		var a := _default(p[0], p[1])
		var b := _default(p[2], p[3])
		if a == "" or a != b:
			bad.append("%s %s / %s %s" % [p[1], a, p[3], b])
	_t._check(bad.is_empty(), "aerial review: the ocean's painted sea and haze match the far plane's numbers %s" % str(bad))
	var tone_a := _vec3(ocean, "range_haze_tone")
	var tone_b := _vec3(relief, "range_haze_tone")
	_t._check(tone_a != "" and tone_a == tone_b, "aerial review: the ocean's range_haze_tone is the plane's (%s / %s)" % [tone_a, tone_b])
	# The painted far sea is linear handed through cs_out() on the ocean, as on the plane.
	_t._check(ocean.contains("fb = cs_out(fb);") and ground.contains("aerial_review && water > 0.5"),
		"aerial review: both seas are worked out in linear light and painted the same way")


## The city put the switch on every material it fixes.
func _materials(city: Node3D) -> void:
	var ground: ShaderMaterial = city.get("_ground_material") as ShaderMaterial
	_t._check(ground != null and ground.get_shader_parameter("aerial_review") == true,
		"aerial review: the horizon plane paints its sea on the ocean's window and keeps its lit band undimmed at night")
	_t._check(PropFactory.ocean_material().get_shader_parameter("aerial_sea") == true,
		"aerial review: the ocean chunks paint their far water like the plane")
	_t._check(PropFactory.terrain_material().get_shader_parameter("aerial_mottle") == true,
		"aerial review: the hill terrain breaks its mottle tile up from the air")
	var rf := RockFar.current
	if rf == null:
		_t._check(not RockOutcrops.enabled, "aerial review: the far rock exists (or ROCKS=0)")
		return
	var mats: Array = rf.get("_materials")
	var on := 0
	for m: ShaderMaterial in mats:
		if m.get_shader_parameter("aerial_haze") == true:
			on += 1
	_t._check(on > 0, "aerial review: the far tors take the plane's layered haze (%d of %d materials)" % [on, mats.size()])


## The mottle's change starts past a pixel footprint the hill shells never reach (their layers go
## by 75 m, where a pixel is ~0.12 m at 720 lines): the near grass stays as the shells copy it.
func _mottle_near_untouched() -> void:
	var px: Variant = PropFactory.terrain_material().get_shader_parameter("mottle_far_px")
	if px == null:
		px = Vector2(0.28, 0.75)
	_t._check(px is Vector2 and (px as Vector2).x >= 0.2 and (px as Vector2).y > (px as Vector2).x,
		"aerial review: the mottle changes only past a %.2f m pixel (the shells' range draws it as before)" % (px as Vector2).x)


## The far crowns' gain is a colour change only, and nothing at all with the switch off.
func _canopy_gain() -> void:
	var cols: Array = [Color(0.2, 0.3, 0.1, 1.0), Color(0.1, 0.2, 0.05, 0.5), Color(0.4, 0.4, 0.4, 1.0)]
	var copy := cols.duplicate()
	AerialReview.darken_city_canopy(cols, 1)
	var ok: bool = cols[0] == copy[0] and cols.size() == 3
	for i in range(1, 3):
		var a: Color = cols[i]
		var b: Color = copy[i]
		ok = ok and is_equal_approx(a.r, b.r * AerialReview.CITY_CANOPY_GAIN) and is_equal_approx(a.a, b.a)
	var was := AerialReview.enabled
	AerialReview.enabled = false
	var off := copy.duplicate()
	AerialReview.darken_city_canopy(off, 0)
	AerialReview.enabled = was
	_t._check(ok and off == copy, "aerial review: the far city's crowns are darkened from their own index on, colour only, none with the switch off")


func _source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


## A float uniform's default, as written.
func _default(src: String, name: String) -> String:
	var re := RegEx.create_from_string("uniform float " + name + "\\b[^=;]*=\\s*([-0-9.]+)\\s*;")
	var m := re.search(src)
	return m.get_string(1) if m else ""


func _vec3(src: String, name: String) -> String:
	var re := RegEx.create_from_string("uniform vec3 " + name + "\\s*=\\s*(vec3\\([^)]*\\))\\s*;")
	var m := re.search(src)
	return m.get_string(1) if m else ""
