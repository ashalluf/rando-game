extends RefCounted
## The pale box round the player's car (docs/HANDOFF.md "The pale box round the player's car"), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The box was the car lamps' halo quads (car_lights.gdshader parts 6 and 7): never collapsed by
## day, written into ALBEDO with ALPHA left at 1, so the renderer mixed the fog colour into them and
## added a haze-grey square round each tail lamp of every running car (the player's is the one the
## chase camera sits behind). Checks that every additive shader either keeps the fog out
## (fog_disabled) or writes a coverage alpha, that the car lamps' halo branch does, that
## af_cover() hands back the light exactly with no alpha where there is none (a GDScript copy of
## shaders/additive_fog.gdshaderinc), and that a running car's lamps still carry the halo quads.

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	_additive_shaders()
	_cover()
	_car_lamps()


func _additive_shaders() -> void:
	var bad: Array = []
	var n := 0
	var dir := DirAccess.open("res://shaders")
	for f: String in dir.get_files():
		if not f.ends_with(".gdshader"):
			continue
		var src := FileAccess.get_file_as_string("res://shaders/" + f)
		var mode := ""
		for line: String in src.split("\n"):
			if line.strip_edges().begins_with("render_mode"):
				mode = line
				break
		if not mode.contains("blend_add"):
			continue
		n += 1
		var writes_alpha := RegEx.create_from_string("\\bALPHA\\s*=").search(src) != null
		if not mode.contains("fog_disabled") and not writes_alpha:
			bad.append(f)
	_t._check(n > 10 and bad.is_empty(),
		"every additive shader keeps the fog colour off its dark quad (fog_disabled or a coverage alpha; %d shaders, bad: %s)" % [n, bad])
	var car := FileAccess.get_file_as_string("res://shaders/car_lights.gdshader")
	var halo := car.find("if (part > 5.5) {\n\t\t// The halo's light")
	var halo_end := car.find("} else {", halo)
	var branch := car.substr(halo, halo_end - halo) if halo >= 0 and halo_end > halo else ""
	_t._check(car.contains("additive_fog.gdshaderinc") and branch.contains("af_cover(") and branch.contains("ALPHA = "),
		"the car lamps' halos write their coverage as the alpha (no grey square round a running car's lamps)")
	var inc := FileAccess.get_file_as_string("res://shaders/additive_fog.gdshaderinc")
	_t._check(inc.contains("const float AF_COVER_GAIN = %.1f;" % AF_COVER_GAIN),
		"additive_fog.gdshaderinc's gain is the checks' copy (%.1f)" % AF_COVER_GAIN)


const AF_COVER_GAIN := 64.0


## additive_fog.gdshaderinc's af_cover(), in GDScript.
static func af_cover(light: Vector3) -> Vector4:
	var m := maxf(light.x, maxf(light.y, light.z))
	var a := clampf(m * AF_COVER_GAIN, 0.0, 1.0)
	var rgb := light / a if a > 0.0 else Vector3.ZERO
	return Vector4(rgb.x, rgb.y, rgb.z, a)


func _cover() -> void:
	var worst := 0.0
	for light: Vector3 in [Vector3(2.4, 0.4, 0.1), Vector3(0.01, 0.002, 0.0), Vector3(1e-5, 0.0, 0.0), Vector3(0.5, 0.5, 0.5)]:
		var o := af_cover(light)
		var back := Vector3(o.x, o.y, o.z) * o.w
		worst = maxf(worst, (back - light).length() / maxf(light.length(), 1e-9))
	var dark := af_cover(Vector3.ZERO)
	_t._check(worst < 1e-5 and dark.w == 0.0 and af_cover(Vector3(1.0, 0.2, 0.1)).w == 1.0,
		"af_cover: the blend gives back the light exactly (worst %.1e), no light no alpha, a bright light full alpha" % worst)


func _car_lamps() -> void:
	var mesh := PropFactory.vehicle_lights(1.9, 4.8, 0.7, -0.24, 0.8)
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	var path := mat.shader.resource_path if mat and mat.shader else ""
	_t._check(path == "res://shaders/car_lights.gdshader",
		"a car's lamps wear car_lights.gdshader (the shader the fix is in; got %s)" % path)
