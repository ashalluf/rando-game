extends RefCounted
## The container terminal at night refcam (PortNight, tools/refcams/cameras_w7.json's port_night), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The camera row: 22:00 clear, on the quay at eye height, the port clock held. The floods: a source
## at every port chunk's mast and every quay crane's portal lamps, TRUE world, handed to both port
## materials; the GDScript copy agrees with the shader's numbers; their light strong under a mast and
## nothing far outside the terminal. The halos, the pools, the deckhouse windows and the A/B.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera()
	_shaders()
	var plan: CityPlan = city.plan
	if plan == null or plan.macro == null:
		return
	_sources(plan)
	_materials(plan)
	_extras()


func _camera() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w7.json", FileAccess.READ)
	_t._check(f != null, "cameras_w7.json is there")
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "port_night":
				row = c
	_t._check(not row.is_empty(), "cameras_w7.json has the port_night row")
	if row.is_empty():
		return
	_t._check(absf(float(row.hour) - 22.0) < 0.01 and String(row.weather) == "clear", "port_night is 22:00, clear")
	var eye: Array = row.eye
	var p := Vector2(float(eye[0]), float(eye[2]))
	var port := Rect2(2750.0, 5935.0, 630.0, 560.0)
	_t._check(port.has_point(p) and p.y > port.end.y - 42.0 and bool(row.get("agl", false)) and float(eye[1]) < 3.0,
		"the eye stands on the quay's apron at eye height (%s)" % [p])
	_t._check(row.has("port_t"), "port_night holds the port's clock (port_t)")
	var shot := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_t._check(shot.contains("func _port_clock(") and shot.contains("cam.has(\"port_t\")"), "refcams_shot.gd reads a row's port_t")


func _shaders() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/port_flood.gdshaderinc")
	_t._check(inc.contains("uniform float port_night = 0.0;"), "port_flood.gdshaderinc keeps the old look until PortNight turns it on")
	_t._check(inc.contains("uniform vec4 flood_src[%d];" % PortNight.MAX_SOURCES), "the shader takes PortNight.MAX_SOURCES floods")
	_t._check(inc.contains("float h = reach * 0.32;") and inc.contains("smoothstep(reach * 0.6, reach, dist)")
		and inc.contains("fall * cone * (0.25 + 0.75 * facing)") and inc.contains("smoothstep(0.0, 0.3, d.y / max(dist, 0.01))"), "the shader's falloff is PortNight.flood_at()'s")
	for path in ["res://shaders/container.gdshader", "res://shaders/port_steel.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		_t._check(src.contains("#include \"res://shaders/port_flood.gdshaderinc\"") and src.contains("if (port_night > 0.5 && flood_count > 0"),
			"%s adds the floods only behind port_night" % path.get_file())
	var steel := FileAccess.get_file_as_string("res://shaders/port_steel.gdshader")
	_t._check(steel.contains("if (vertical && port_night > 0.5) {"), "the deckhouse's new windows are behind port_night")


func _sources(plan: CityPlan) -> void:
	var blocks := PortNight.port_blocks(plan)
	_t._check(blocks.size() >= 9, "the terminal has its port blocks (%d)" % blocks.size())
	var src := PortNight.sources(plan)
	_t._check(src.size() > blocks.size() and src.size() <= PortNight.MAX_SOURCES, "a flood at every mast and the quay cranes (%d sources)" % src.size())
	var pr: Rect2 = plan.macro.port_rect.grow(80.0)
	var inside := true
	var masts := 0
	var cranes := 0
	for s: Vector4 in src:
		inside = inside and pr.has_point(Vector2(s.x, s.z))
		if is_equal_approx(s.w, PortNight.MAST_REACH):
			masts += 1
		elif is_equal_approx(s.w, PortNight.CRANE_REACH):
			cranes += 1
	_t._check(inside, "every flood stands in the terminal")
	_t._check(masts == mini(blocks.size(), PortNight.MAX_SOURCES), "one flood per port chunk's mast (%d of %d)" % [masts, blocks.size()])
	_t._check(cranes >= 4 and cranes % 2 == 0, "each quay crane lights both rails (%d)" % cranes)
	_t._check(PortNight.sources(plan) == src, "the sources are pure (the same twice)")
	# The light: strong at the foot of a mast, nothing far outside the terminal.
	var m := Vector3.ZERO
	for s: Vector4 in src:
		if is_equal_approx(s.w, PortNight.MAST_REACH):
			m = Vector3(s.x, s.y, s.z)
			break
	var under := PortNight.flood_at(src, Vector3(m.x + 4.0, 0.3, m.z + 4.0), Vector3.UP)
	var far := PortNight.flood_at(src, Vector3(pr.position.x - 400.0, 1.0, pr.position.y - 400.0), Vector3.UP)
	_t._check(under > 0.35 and far == 0.0, "the yard under a mast is lit (%.2f), nothing far outside is (%.2f)" % [under, far])
	var toward := PortNight.flood_at(src, Vector3(m.x + 30.0, 5.0, m.z), Vector3.LEFT)
	var away := PortNight.flood_at(src, Vector3(m.x + 30.0, 5.0, m.z), Vector3.RIGHT)
	_t._check(toward > away, "a face turned to a mast is lit more than one turned away (%.2f > %.2f)" % [toward, away])


func _materials(plan: CityPlan) -> void:
	var was := PortNight.enabled
	PortNight.apply(plan)
	var cm := PortKit.container_material()
	var sm := PortKit.steel_material()
	if was:
		_t._check(float(cm.get_shader_parameter("port_night")) > 0.5 and float(sm.get_shader_parameter("port_night")) > 0.5,
			"both port materials have the floods on")
		_t._check(int(cm.get_shader_parameter("flood_count")) == PortNight.sources(plan).size(), "the container shader has every flood")
	PortNight.enabled = false
	PortNight.apply(plan)
	_t._check(float(cm.get_shader_parameter("port_night")) < 0.5 and int(sm.get_shader_parameter("flood_count")) == 0,
		"PORT_NIGHT=0 puts the old look back")
	_t._check(is_equal_approx(PortNight.pool_strength(), 0.5) and is_equal_approx(PortNight.pool_falloff(), 1.5), "PORT_NIGHT=0 keeps the old pools")
	_t._check(PortNight.crane_halos(Vector3.ZERO).is_empty() and PortNight.mast_halo(Vector3.ZERO).is_empty(), "PORT_NIGHT=0 adds no halo")
	PortNight.enabled = was
	PortNight.apply(plan)


func _extras() -> void:
	if not PortNight.enabled:
		return
	_t._check(PortNight.pool_strength() > 0.5, "the yard's pools are stronger")
	if NightAtmos.enabled:
		var h := PortNight.crane_halos(Vector3(10.0, 0.2, 20.0))
		_t._check(h.size() == 4 and String(h[0][0]) == NightAtmos.HALO_KEY, "a halo on each of a crane's four portal lamps")
		var mh := PortNight.mast_halo(Vector3.ZERO)
		_t._check(mh.size() == 1 and absf((mh[0][2] as Transform3D).origin.y - (PortKit.MAST_H - 1.1)) < 0.01, "a halo on the mast's head")
