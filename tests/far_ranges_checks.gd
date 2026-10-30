extends RefCounted
## The far ranges (FarRanges, docs/HANDOFF.md "The far ranges"): checks for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Every number is worked out here from the
## city's own MacroMap (FarRanges.enabled is switched round single synchronous calls and put back),
## so nothing depends on where an earlier check left the player or the streamer. No shader runs
## headless: the shaders are held by their source and by the uniforms the streamer set.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		_t._check(false, "far ranges: the city has a plan and a map")
		return
	var macro: MacroMap = plan.macro
	_t._check(FarRanges.enabled, "far ranges: on in the smoke test (FAR_RANGES=0 is the A/B only)")
	if not FarRanges.enabled:
		return
	_front_range_untouched(macro)
	_feet_stay(macro)
	_no_walls(macro)
	_skylines(macro)
	_bake_is_the_new_shape(macro)
	_shaders(city)


## The height with FarRanges on or off, at once.
func _raw(macro: MacroMap, p: Vector2, on: bool) -> float:
	var was := FarRanges.enabled
	FarRanges.enabled = on
	var h := macro.raw_height_at(p)
	FarRanges.enabled = was
	return h


## The front range carries the sign, the observatory, the hill roads, the estates, the reservoir and
## the ballpark: not a centimetre of it moves (sampled where the back range is still far off).
func _front_range_untouched(macro: MacroMap) -> void:
	var worst := 0.0
	var n := 0
	for i in 40:
		for j in 12:
			var p := Vector2(-1500.0 + i * 160.0, -950.0 - j * 40.0)
			if macro._range_heights_at(p).y > 1.0 or macro._range_heights_at(p).z > 1.0:
				continue
			worst = maxf(worst, absf(_raw(macro, p, true) - _raw(macro, p, false)))
			n += 1
	_t._check(n > 300 and worst < 0.001, "far ranges: the front range's height is unchanged (%d points, worst %.4f m)" % [n, worst])


## The ranges' feet decide CITY against HILLS (zone_at()): the old face is kept to the full-height
## line, so the valley's north edge and the basin's east edge do not move.
func _feet_stay(macro: MacroMap) -> void:
	var moved := 0
	var n := 0
	var worst := 0.0
	for i in 60:
		var x := -1500.0 + i * 110.0
		var emb := macro.embay_at(x)
		for j in 14:
			# Across the back range's foot, in the embay-shifted frame the base uses.
			var z := macro.back_start_z - macro.embay_depth * emb + 60.0 - j * 25.0
			var p := Vector2(x, z)
			var a := _raw(macro, p, true)
			var b := _raw(macro, p, false)
			if b < 40.0:
				n += 1
				worst = maxf(worst, absf(a - b))
				if (a > 0.5) != (b > 0.5):
					moved += 1
	for j in 50:
		for i in 10:
			var p := Vector2(macro.east_start_x - 60.0 + i * 25.0, -2500.0 + j * 120.0)
			var a := _raw(macro, p, true)
			var b := _raw(macro, p, false)
			if b < 40.0:
				n += 1
				worst = maxf(worst, absf(a - b))
				if (a > 0.5) != (b > 0.5):
					moved += 1
	_t._check(n > 200 and moved <= n / 100, "far ranges: the back and east ranges' feet stay where they were (%d of %d foot points change side, worst %.1f m on the low face)" % [moved, n, worst])


## The bases (before erosion) have no step anywhere: a crest pulled onto the old full-height line
## once made a 150 m wall a few metres wide. Steepest base slope over transects across both ranges.
func _no_walls(macro: MacroMap) -> void:
	var steep := 0.0
	var at := Vector2.ZERO
	for i in 24:
		var x := -1500.0 + i * 380.0
		var prev := macro._range_heights_at(Vector2(x, -3000.0)).y
		var z := -3010.0
		while z > -8000.0:
			var h := macro._range_heights_at(Vector2(x, z)).y
			if absf(h - prev) / 10.0 > steep:
				steep = absf(h - prev) / 10.0
				at = Vector2(x, z)
			prev = h
			z -= 10.0
	for j in 24:
		var z := -4000.0 + j * 380.0
		var prev := macro._range_heights_at(Vector2(4900.0, z)).z
		var x := 4910.0
		while x < 8000.0:
			var h := macro._range_heights_at(Vector2(x, z)).z
			if absf(h - prev) / 10.0 > steep:
				steep = absf(h - prev) / 10.0
				at = Vector2(x, z)
			prev = h
			x += 10.0
	_t._check(steep < 1.4, "far ranges: the ranges' bases have no walls (steepest %.2f m/m at %s)" % [steep, at])


## The skylines seen from downtown (north, the back range) and from the east side (east, the east
## range): fewer separate summits and a smoother crest than the old teeth.
func _skylines(macro: MacroMap) -> void:
	for v: Array in [["downtown north", Vector3(2600.0, 120.0, -450.0), 0.0], ["east side", Vector3(2800.0, 150.0, 100.0), -90.0]]:
		var on := _skyline(macro, v[1], v[2], true)
		var off := _skyline(macro, v[1], v[2], false)
		_t._check(on.sharp < off.sharp * 0.8 and on.peaks <= off.peaks,
			"far ranges: the %s skyline is massive ridges, not teeth (sharpness %.2f against %.2f, %d summits against %d)" % [v[0], on.sharp, off.sharp, on.peaks, off.peaks])


func _skyline(macro: MacroMap, eye: Vector3, yaw: float, on: bool) -> Dictionary:
	var was := FarRanges.enabled
	FarRanges.enabled = on
	var fov := 70.0
	var cols := 140
	var sky := PackedFloat32Array()
	for x in cols:
		var az := deg_to_rad(yaw + fov * (0.5 - (x + 0.5) / cols))
		var dir := Vector2(-sin(az), -cos(az))
		var best := -90.0
		var d := 400.0
		while d < 12000.0:
			var p := Vector2(eye.x, eye.z) + dir * d
			best = maxf(best, rad_to_deg(atan2(macro.raw_height_at(p) - d * d / 12742000.0 - eye.y, d)))
			d += 25.0 + d * 0.01
		sky.append(best)
	FarRanges.enabled = was
	return FarRanges.skyline_stats(sky, fov / cols)


## The horizon plane is the bake, and the bake is cached on disk (LoadCache): it must hold the new
## shape, not a launch's old one.
func _bake_is_the_new_shape(macro: MacroMap) -> void:
	var img: Image = macro.bake_height
	if img == null:
		_t._check(false, "far ranges: the bake's height image exists")
		return
	var res := img.get_width()
	var span := 16000.0
	var worst := 0.0
	var n := 0
	for k in 12:
		var px := int(res * (0.42 + 0.04 * k))
		var py := int(res * 0.08)
		var pos := Vector2((px + 0.5) * span / res - span * 0.5, (py + 0.5) * span / res - span * 0.5)
		var want := macro.height_at(pos)
		var got := img.get_pixel(px, py).r * MacroMap.BAKE_HEIGHT_SCALE
		worst = maxf(worst, absf(want - got))
		n += 1
	_t._check(worst < 1.0, "far ranges: the horizon plane's bake is the new back range (%d texels, worst %.2f m)" % [n, worst])


func _shaders(city: Node3D) -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/macro_relief.gdshaderinc")
	_t._check(inc.contains("uniform float crag_shape") and inc.contains("mix(1.0 - abs(v), abs(v), crag_shape)"),
		"far ranges: the plane's crags can turn over (crag_shape in macro_relief.gdshaderinc)")
	var miss: Array[String] = []
	for p: String in ["res://shaders/macro_ground.gdshader", "res://shaders/far_canopy.gdshader", "res://shaders/far_estate.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		if not src.contains("range_haze_amount(") or not src.contains("range_haze_color("):
			miss.append(p.get_file())
	_t._check(miss.is_empty(), "far ranges: the ground, the far canopy and the far estates sit in the same layered haze (%s)" % (", ".join(miss) + " missing" if miss else "all three"))
	# The haze function as the include writes it, with its defaults: nothing on the streamed tiles,
	# denser at a ridge's foot than at its crest, never a white-out.
	var u := {}
	var re := RegEx.create_from_string("uniform float (range_haze\\w*)\\s*(?::[^=]*)?=\\s*([0-9.]+)")
	for m in re.search_all(inc):
		u[m.get_string(1)] = m.get_string(2).to_float()
	var ok := u.size() >= 5
	if ok:
		var amt := func(d: float, y: float) -> float:
			var a := 1.0 - exp(-maxf(d - float(u.range_haze_from), 0.0) / float(u.range_haze_reach))
			return float(u.range_haze) * a * lerpf(1.0, float(u.range_haze_keep), smoothstep(0.0, float(u.range_haze_top), y))
		var near: float = amt.call(900.0, 100.0)
		var foot: float = amt.call(5000.0, 150.0)
		var crest: float = amt.call(5000.0, 1100.0)
		var far: float = amt.call(12000.0, 0.0)
		ok = near == 0.0 and foot > crest * 1.4 and foot > 0.1 and far < 0.7
		_t._check(ok, "far ranges: the haze is layered (nothing at 900 m, %.2f at a ridge's foot 5 km off, %.2f at its crest, %.2f at 12 km)" % [foot, crest, far])
	else:
		_t._check(false, "far ranges: the haze uniforms are in macro_relief.gdshaderinc (%d found)" % u.size())
	var mat = city.get("_ground_material")
	var canopy = city.get("_canopy_material")
	var wired := mat is ShaderMaterial and canopy is ShaderMaterial \
		and float((mat as ShaderMaterial).get_shader_parameter("crag_shape")) == 1.0 \
		and float((canopy as ShaderMaterial).get_shader_parameter("crag_shape")) == 1.0
	_t._check(wired, "far ranges: the streamer turned the crags over on the plane and the far canopy (FarRanges.apply)")
