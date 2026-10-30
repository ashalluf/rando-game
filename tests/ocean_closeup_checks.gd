extends RefCounted
## The Pacific close up (OceanCloseup, shaders/ocean_closeup.gdshaderinc, waterline_wet, pile_wet)
## for tests/smoke_test.gd. Loaded at run time (not named there). Reads shader sources, the plan's
## piers and the ocean material; sets the A/B global and puts it back, so it does not care what ran
## before it or leave anything for what runs after.
##
## Checks: the close-up pass is fragment-only (the vertex stage, which SeaSurface mirrors, never
## reads it) and faded with `detail` before the hand-over; the ocean takes no texture sampler (the
## web's budget); the pile grids sit on the piers' real piles and out in the sea; the GDScript
## pile distance agrees with the shader's rule; Weather hands the grids to the ocean; the A/B
## switch turns the global, the grids' pass and the piers' pile materials off.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var ocean := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	var inc := FileAccess.get_file_as_string("res://shaders/ocean_closeup.gdshaderinc")
	_t._check(ocean.contains("#include \"res://shaders/ocean_closeup.gdshaderinc\""), "ocean close-up: ocean.gdshader includes the close-up pass")
	# Fragment only: nothing in the include touches VERTEX, and the vertex stage calls none of it.
	var vstart := ocean.find("void vertex()")
	var fstart := ocean.find("void fragment()")
	var vbody := ocean.substr(vstart, fstart - vstart) if vstart >= 0 and fstart > vstart else ""
	_t._check(vbody != "" and not vbody.contains("oc_") and not vbody.contains("closeup") and not inc.contains("VERTEX") and not inc.contains("void vertex"),
		"ocean close-up: the pass is fragment-only (SeaSurface's vertex stage is untouched)")
	_t._check(ocean.contains("float near_c = closeup * detail;"), "ocean close-up: every close-up term is faded with the hand-over's detail")
	var samplers := ocean.count("sampler2D") + inc.count("sampler2D")
	_t._check(samplers == 0, "ocean close-up: the ocean still samples no texture (%d)" % samplers)
	var gl := FileAccess.get_file_as_string("res://project.godot")
	_t._check(gl.contains("ocean_closeup={"), "ocean close-up: the ocean_closeup shader global is declared")
	var pier_sh := FileAccess.get_file_as_string("res://shaders/pier_park.gdshader")
	var pile_sh := FileAccess.get_file_as_string("res://shaders/pile_wet.gdshader")
	_t._check(pier_sh.contains("waterline_wet.gdshaderinc") and pile_sh.contains("waterline_wet.gdshaderinc"),
		"ocean close-up: the pier park's piles and the beach piers' piles carry the waterline")

	# The pile grids: on the piers' real piles, out at sea.
	var grids := OceanCloseup.pile_grids()
	_t._check(grids.size() >= 3 and grids.size() <= OceanCloseup.MAX_GRIDS, "ocean close-up: the piers give pile grids (%d)" % grids.size())
	var plan: Variant = city.get("plan") if city else null
	var macro: Variant = plan.get("macro") if plan else null
	var wet := 0
	var piles := 0
	for g: Array in grids:
		var a: Vector4 = g[0]
		var b: Vector4 = g[1]
		for i in int(b.x):
			for j in int(b.y):
				var p := Vector2(a.x + a.z * i, a.y + a.w * j)
				piles += 1
				if macro and float(macro.call("coast_x", p.y)) > p.x:
					wet += 1
	_t._check(piles > 40 and wet * 2 > piles, "ocean close-up: most grid piles stand in the sea (%d of %d)" % [wet, piles])
	# The pier park's first sea-end pile, as PierPark._piles() builds it.
	var pier_ok := false
	for lm: Dictionary in Landmarks.all():
		if str(lm.id) == "pier":
			var at: Vector2 = lm.anchor
			var want := at + Vector2(PierPark.MAIN.end.x - 4.0, PierPark.MAIN.position.y + 2.0)
			pier_ok = _dist(grids, want) < -0.3
	_t._check(pier_ok, "ocean close-up: the pier park's shore-end pile is in its grid")
	# The shader's rule in GDScript: inside a pile is negative, half a step off is clear water.
	var g0: Array = grids[0] if not grids.is_empty() else [Vector4.ZERO, Vector4.ZERO]
	var a0: Vector4 = g0[0]
	var b0: Vector4 = g0[1]
	var mid := Vector2(a0.x + a0.z * 0.5, a0.y + a0.w * 0.5)
	_t._check(_dist(grids, Vector2(a0.x, a0.y)) < 0.0 and _dist(grids, mid) > b0.z, "ocean close-up: the pile distance is negative in a pile and clear between them")

	# Weather hands the grids to the ocean material.
	var mat := PropFactory.ocean_material()
	OceanCloseup.apply(mat)
	_t._check(int(mat.get_shader_parameter("pile_count")) == mini(grids.size(), OceanCloseup.MAX_GRIDS), "ocean close-up: the ocean material carries the pile grids")
	_t._check(OceanCloseup.pile_material(Color.GRAY, 0.9, false, null) is ShaderMaterial, "ocean close-up: the piers' piles wear the waterline material")

	# The A/B.
	var old := OS.get_environment("OCEAN_CLOSEUP")
	OS.set_environment("OCEAN_CLOSEUP", "0")
	OceanCloseup.apply(mat)
	# The dummy renderer (headless) keeps no globals: it hands back null.
	var off_raw = RenderingServer.global_shader_parameter_get("ocean_closeup")
	var off_global := float(off_raw) if off_raw != null else 0.0
	var fb := StandardMaterial3D.new()
	var off_mat := OceanCloseup.pile_material(Color.GRAY, 0.9, false, fb)
	OS.set_environment("OCEAN_CLOSEUP", old)
	OceanCloseup.apply(mat)
	var on_raw = RenderingServer.global_shader_parameter_get("ocean_closeup")
	var on_global := float(on_raw) if on_raw != null else (1.0 if old != "0" else 0.0)
	_t._check(is_zero_approx(off_global) and is_equal_approx(on_global, 1.0 if old != "0" else 0.0) and off_mat == fb,
		"ocean close-up: OCEAN_CLOSEUP=0 turns the global and the pile materials off (%.1f / %.1f)" % [off_global, on_global])


## ocean_closeup.gdshaderinc oc_pile_dist() in GDScript.
static func _dist(grids: Array, w: Vector2) -> float:
	var best := 1e6
	for g: Array in grids:
		var a: Vector4 = g[0]
		var b: Vector4 = g[1]
		var st := Vector2(a.z if absf(a.z) > 0.001 else 1.0, a.w if absf(a.w) > 0.001 else 1.0)
		var k := ((w - Vector2(a.x, a.y)) / st + Vector2(0.5, 0.5)).floor()
		k = k.clamp(Vector2.ZERO, Vector2(maxf(b.x - 1.0, 0.0), maxf(b.y - 1.0, 0.0)))
		var c := Vector2(a.x, a.y) + k * Vector2(a.z, a.w)
		best = minf(best, w.distance_to(c) - b.z)
	return best
