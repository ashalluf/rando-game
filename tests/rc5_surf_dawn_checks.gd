extends RefCounted
## The surf_dawn refcam (rc5-surf-dawn) for tests/smoke_test.gd, loaded at run time. Checks: the
## camera row is in cameras_w8.json (07:00 clear, its beach_stage and surf_gain keys); SurfRide's
## crest is where surf.gdshaderinc puts wave n (phase a whole number, the drawn surface highest
## there), the rider stands on its front face (landward of the crest, on rising water), the stage
## picks a wave throwing its lip; dawn patrol seats extra surfers at dawn only; the ocean material
## carries the A/B's uniforms (ripple_rot, crest_carry, glint_keep, capillary_rot) and the shaders
## their branches. RC5_SURF_DAWN=0 is the A/B.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_row()
	_shaders()
	_dawn()
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		_t._check(false, "rc5 surf dawn: the city has a plan")
		return
	_ride(plan.macro)


func _row() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "surf_dawn":
				row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 7.0) and String(row.get("weather", "")) == "clear"
		and row.has("beach_stage") and float(row.get("surf_gain", 0.0)) > 1.0,
		"rc5 surf dawn: the surf_dawn row is in cameras_w8.json, 07:00 clear, staging a ride on a bigger sea")


func _shaders() -> void:
	var on := SurfRide.enabled
	var mat := PropFactory.ocean_material()
	RcSurfDawn.apply_ocean(mat)
	_t._check(is_equal_approx(float(mat.get_shader_parameter("ripple_rot")), 1.0 if on else 0.0)
		and is_equal_approx(float(mat.get_shader_parameter("crest_carry")), 1.0 if on else 0.0)
		and is_equal_approx(float(mat.get_shader_parameter("capillary_rot")), 1.0 if on else 0.0)
		and is_equal_approx(float(mat.get_shader_parameter("glint_keep")), RcSurfDawn.GLINT_KEEP if on else 1.0),
		"rc5 surf dawn: the ocean material's ripple_rot, crest_carry, capillary_rot and glint_keep follow RC5_SURF_DAWN")
	var src := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	_t._check(src.contains("vec2 ripple_grad(") and src.contains("transpose(rot)") and src.contains("crest_carry *")
		and not src.contains("vec3 r1 = noised(rp)"),
		"rc5 surf dawn: ocean.gdshader takes its ripple from ripple_grad() and carries the crest's glow over its top")
	var inc := FileAccess.get_file_as_string("res://shaders/ocean_closeup.gdshaderinc")
	_t._check(inc.contains("uniform float glint_keep") and inc.contains("glint_keep);") and inc.contains("capillary_rot > 0.5"),
		"rc5 surf dawn: ocean_closeup thins the glitter cells and turns the capillaries' second octave")


func _dawn() -> void:
	var on := SurfRide.enabled
	_t._check((RcSurfDawn.dawn_surfers(7.0, 0.5) > 0) == on and RcSurfDawn.dawn_surfers(14.0, 1.0) == 0
		and RcSurfDawn.dawn_surfers(5.0, 1.0) == 0 and RcSurfDawn.dawn_surfers(20.0, 1.0) == 0,
		"rc5 surf dawn: dawn patrol seats extra surfers from first light to mid morning only")


func _ride(m: MacroMap) -> void:
	var p := Surf.params(1.0, 1.7)
	var st := [1.0, 0.0, p[0], p[1]]
	var shape: Vector4 = p[0]
	var extra: Vector4 = p[1]
	var bad := 0
	var face_bad := 0
	var tried := 0
	for z: float in [400.0, 800.0, 1200.0]:
		for t: float in [0.0, 3.1, 11.7]:
			var n := SurfRide.wave_at(m, shape, z, shape.w, t)
			var sc := SurfRide.crest_s(m, shape, z, n, t)
			var pc := SurfRide.point(m, z, sc)
			var phi := (sc + SurfRide._wob(pc)) / shape.y + t / shape.z
			if absf(phi - n) > 0.02:
				bad += 1
			# The drawn surf (SeaSurface's mirror of the shader) is higher at the crest than half a
			# crest spacing either side of it.
			var hc := SeaSurface.surf_height(shape, extra, pc, sc, t)
			var hl := SeaSurface.surf_height(shape, extra, SurfRide.point(m, z, sc - shape.y * 0.5), sc - shape.y * 0.5, t)
			var hs := SeaSurface.surf_height(shape, extra, SurfRide.point(m, z, sc + shape.y * 0.5), sc + shape.y * 0.5, t)
			if hc <= hl or hc <= hs:
				bad += 1
			var rp := SurfRide.ride_point(m, st, z, n, t)
			tried += 1
			if rp.x >= sc or sc - rp.x > SurfRide.face_width(shape, extra, sc) or rp.z <= 0.0:
				face_bad += 1
	_t._check(bad == 0, "rc5 surf dawn: SurfRide's crest is where the shader's wave n is, the surf highest there (%d off)" % bad)
	_t._check(face_bad == 0, "rc5 surf dawn: the rider stands on the front face, landward of the crest on rising water (%d of %d off)" % [face_bad, tried])
	var pick := SurfRide.stage_pick(m, st, 800.0, 0.0)
	var sc0 := SurfRide.crest_s(m, shape, pick.x, pick.y, 0.0)
	var g := SurfRide.gain(m, shape, pick.x, pick.y)
	var sig := sc0 / maxf(shape.w * pow(g, 0.8), 2.0)
	_t._check(absf(pick.x - 800.0) <= SurfRide.STAGE_REACH + 0.01 and sig > 0.8 and sig < 1.1,
		"rc5 surf dawn: the staged wave is within reach and throwing its lip (crest at %.2f of its break)" % sig)
