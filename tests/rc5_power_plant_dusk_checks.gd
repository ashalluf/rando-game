extends RefCounted
## The power plant at dusk (RcPowerPlant, wave 8 refcam power_plant_dusk), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the camera row (18:50 clear, on the sand north of the plant, looking at it); the lamps
## that light the plant (sources(): a fair number, all at the plant, the stacks uplit) and the
## shared material carrying them; the GDScript copy of the falloff lights a hall's wall under a
## wall pack and nothing far off, and the shader include carries the same numbers; the window
## bands stand clear of the depth buffer's step; RC5_POWER_PLANT off hands the material rc5 0.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_camera_row(plan)
	if not PowerPlant.enabled:
		return
	var lay := PowerPlant.layout(plan)
	if lay.is_empty() or not bool(lay.ok):
		return
	_sources(plan, lay)
	_shader()
	_switch(plan)


func _camera_row(plan: CityPlan) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in (parsed as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "power_plant_dusk":
				row = c
	_t._check(not row.is_empty() and absf(float(row.get("hour", 0.0)) - 18.83) < 0.01 and String(row.get("weather", "")) == "clear",
		"the power_plant_dusk refcam row is in cameras_w8.json (18:50 clear)")
	if row.is_empty() or not PowerPlant.enabled:
		return
	var lay := PowerPlant.layout(plan)
	if lay.is_empty():
		return
	var eye: Array = row.eye
	var e := Vector2(float(eye[0]), float(eye[2]))
	var r: Rect2 = lay.rect
	var m := plan.macro
	var on_sand := e.x < m.coast_x(e.y) + m.beach_width_at(e.y) and e.x > m.coast_x(e.y) - 4.0
	# Forward is -Z: yaw 0 looks north; the stacks' bearing from the eye within the half field of view.
	var yaw := deg_to_rad(float(eye[3]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var st: Vector3 = lay.stacks[0]
	var to_stack := (Vector2(st.x, st.z) - e).normalized()
	_t._check(on_sand and e.y < r.position.y and fwd.dot(to_stack) > cos(deg_to_rad(30.0)),
		"the camera stands on the sand north of the plant (%s, sand %s) looking at its stacks (%.2f)" % [e, on_sand, fwd.dot(to_stack)])


func _sources(plan: CityPlan, lay: Dictionary) -> void:
	var src := RcPowerPlant.sources(plan)
	var r: Rect2 = (lay.rect as Rect2).grow(20.0)
	var inside := true
	var up := 0
	for s: Vector4 in src:
		inside = inside and r.has_point(Vector2(s.x, s.z))
		if s.w > 500.0:
			up += 1
	_t._check(src.size() >= 24 and src.size() <= RcPowerPlant.MAX_SOURCES and inside,
		"the plant's lamps that light it: %d (24..%d), all at the plant (%s)" % [src.size(), RcPowerPlant.MAX_SOURCES, inside])
	_t._check(up == 4, "each tall stack is uplit by two floods at its foot (%d)" % up)
	# Under a turbine hall wall pack: the wall below it is lit; 300 m off nothing is.
	var hall: Dictionary = {}
	for p: Dictionary in lay.pieces:
		if String(p.kind) == "turbine_hall":
			hall = p
	if hall.is_empty():
		_t._check(false, "the plant has a turbine hall")
		return
	var c: Vector2 = hall.c
	var sz: Vector3 = hall.size
	var g := PowerPlant.BASE_Y + plan.macro.relief_at(c)
	var pack: Vector3 = RcPowerPlant.hall_packs(sz)[0]
	var wall := Vector3(c.x + pack.x - signf(pack.x) * 0.35, g + 4.0, c.y + pack.z)
	var lit := RcPowerPlant.flood_at(src, wall, Vector3(signf(pack.x), 0.0, 0.0))
	var far := RcPowerPlant.flood_at(src, wall + Vector3(-300.0, 0.0, 0.0), Vector3.UP)
	_t._check(lit > 0.1 and lit <= RcPowerPlant.CAP and far == 0.0,
		"a wall pack lights the hall's wall under it (%.2f) and nothing 300 m off (%.2f)" % [lit, far])
	var m := PowerPlantKit.material()
	RcPowerPlant.apply(plan)
	_t._check(float(m.get_shader_parameter("rc5")) > 0.5 and int(m.get_shader_parameter("pp_src_count")) == src.size(),
		"the plant's material carries the lamps (%s)" % m.get_shader_parameter("pp_src_count"))


func _shader() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/rc5_power_plant.gdshaderinc")
	var sh := FileAccess.get_file_as_string("res://shaders/power_plant.gdshader")
	_t._check(inc.contains("reach * 0.22") and inc.contains("reach * 0.45") and inc.contains("reach * 0.3;")
		and sh.contains("rc5_power_plant.gdshaderinc") and sh.contains("pp_flood(") and sh.contains("pp_window("),
		"power_plant.gdshader lights the plant from its lamps and draws the windows by bay (the include's numbers are RcPowerPlant.flood_at()'s)")
	# 200 m off, a 24-bit depth buffer with the camera's near plane steps ~5 cm: the old 7 cm z-fought.
	_t._check(RcPowerPlant.GLASS_OUT + 0.04 > 0.2 and RcPowerPlant.GLASS_OUT + 0.04 < 0.36,
		"the window bands stand clear of the wall (%.2f m) and behind the pilasters' fronts (0.36 m)" % (RcPowerPlant.GLASS_OUT + 0.04))


func _switch(plan: CityPlan) -> void:
	var m := PowerPlantKit.material()
	RcPowerPlant.enabled = false
	RcPowerPlant.apply(plan)
	var off := float(m.get_shader_parameter("rc5"))
	var gl := RcPowerPlant.glass_out(0.03)
	RcPowerPlant.enabled = true
	RcPowerPlant._applied.clear()
	RcPowerPlant.apply(plan)
	_t._check(off == 0.0 and is_equal_approx(gl, 0.03) and float(m.get_shader_parameter("rc5")) > 0.5,
		"RC5_POWER_PLANT off puts the plant back (rc5 %s, glass %.2f) and on again restores it" % [off, gl])
