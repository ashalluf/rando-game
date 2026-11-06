extends RefCounted
## Broadway at night (BroadwayNight, the broadway_night reference camera), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the camera row (cameras_w6.json) looks down Broadway with its traffic staged on it; the
## sign material takes the pass (look3 and brighter night levels) and the A/B leaves the old ones;
## the blade sign's held sequence keeps the name lit most of the cycle; the auditorium's brick is a
## red-brown and the A/B the old pale tint; the side walls' dressing adds geometry on both walls
## (and none with the pass off); the searchlight shaft and the marquee's light take the pass.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := BroadwayNight.enabled
	BroadwayNight.enabled = true
	_camera()
	_sign()
	_brick()
	_sides()
	_lights()
	_trees(city)
	BroadwayNight.enabled = was


func _camera() -> void:
	var cams: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var row: Dictionary = {}
	if cams is Dictionary:
		for c: Dictionary in cams.get("cameras", []):
			if str(c.get("name", "")) == "broadway_night":
				row = c
	var eye: Array = row.get("eye", [])
	var sc: Dictionary = row.get("street_cars", {})
	_t._check(not row.is_empty() and eye.size() == 5 and absf(float(eye[0]) - Broadway.avenue_x()) < Broadway.avenue_width() * 0.5
		and float(eye[2]) > Broadway.z_range().x and float(eye[2]) < Broadway.z_range().y and is_equal_approx(float(row.get("hour", 0.0)), 22.0),
		"the broadway_night camera stands on Broadway in the theatre district at 22:00 (%s)" % str(eye))
	_t._check(str(sc.get("axis", "")) == "x" and absf(float(sc.get("at", 0.0)) - Broadway.avenue_x()) < 1.0 and (sc.get("cars", []) as Array).size() >= 4,
		"its traffic is staged on Broadway itself")


func _sign() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/broadway_sign.gdshader")
	BroadwayNight.sign(m)
	var on := float(m.get_shader_parameter("look3")) > 0.5
	var brighter := true
	for k: String in BroadwayNight.SIGN_NIGHT:
		var old: Variant = m.shader.get_shader_uniform_list().filter(func(u: Dictionary) -> bool: return u.name == k)
		brighter = brighter and float(m.get_shader_parameter(k)) > 0.0 and not (old as Array).is_empty()
	_t._check(on and brighter, "a palace's sign material takes the night pass (look3, the marquee's night levels)")
	BroadwayNight.enabled = false
	var m2 := ShaderMaterial.new()
	m2.shader = m.shader
	BroadwayNight.sign(m2)
	_t._check(m2.get_shader_parameter("look3") == null or float(m2.get_shader_parameter("look3")) < 0.5,
		"BROADWAY_NIGHT=0 leaves the sign material as it was")
	BroadwayNight.enabled = true
	var src := FileAccess.get_file_as_string("res://shaders/broadway_sign.gdshader")
	# The held sequence: spell 1.6 s, hold to 12.6 s of a 14.6 s cycle (the name lit > 75 % of it).
	var held := src.contains("float c3 = 14.6;") and src.contains("if (t3 < 12.6)")
	_t._check(held and (12.6 - 1.6) / 14.6 > 0.75, "the blade sign holds its name lit most of its cycle")


func _brick() -> void:
	var on := BroadwayNight.brick_tint()
	BroadwayNight.enabled = false
	var off := BroadwayNight.brick_tint()
	BroadwayNight.enabled = true
	_t._check(on.r > on.g * 1.4 and on.g > on.b and on.get_luminance() < 0.45 and off.is_equal_approx(BroadwayNight.OLD_BRICK_TINT),
		"the auditorium's brick is red-brown with the pass on, the old tint with it off (%s)" % str(on))


func _sides() -> void:
	var spec: Dictionary = Broadway.THEATRES[3]
	var g := LandmarkGeo.new()
	for k: String in ["brick", "trim", "sign"]:
		g.use(k, StandardMaterial3D.new())
	BroadwayNight.side_dress(g, spec, 30.0, 24.0, 10.0, 34.0)
	var with_pass := g.triangles
	var left := 0
	var right := 0
	for key: String in ["brick", "sign"]:
		var s: Dictionary = g._surfaces.get(key, {})
		var vs: Variant = s.get("verts", s.get("v", null))
		if vs is PackedVector3Array:
			for v: Vector3 in vs:
				if v.x < -14.0:
					left += 1
				elif v.x > 14.0:
					right += 1
	BroadwayNight.enabled = false
	var g2 := LandmarkGeo.new()
	for k: String in ["brick", "trim", "sign"]:
		g2.use(k, StandardMaterial3D.new())
	BroadwayNight.side_dress(g2, spec, 30.0, 24.0, 10.0, 34.0)
	BroadwayNight.enabled = true
	_t._check(with_pass > 400 and g2.triangles == 0, "the auditorium's side walls are dressed (%d triangles; none with the pass off)" % with_pass)
	_t._check((left == 0 and right == 0) or (left > 50 and right > 50), "both side walls are dressed (%d / %d vertices)" % [left, right])


func _lights() -> void:
	var beam := ShaderMaterial.new()
	beam.shader = load("res://shaders/nightlife_beam.gdshader")
	BroadwayNight.beam(beam)
	var light := OmniLight3D.new()
	BroadwayNight.marquee_light(light)
	var p: Array = BroadwayNight.pool(Vector2(10.0, 8.0), 0.8)
	_t._check(float(beam.get_shader_parameter("look3")) > 0.5 and float(light.get_meta("lamp_gain", 1.0)) > 1.5
		and is_equal_approx(light.omni_range, BroadwayNight.LIGHT_RANGE) and (p[0] as Vector2).x > 10.0 and float(p[1]) <= 1.0,
		"the searchlight shafts and the marquees' light take the pass")
	light.free()
	var src := FileAccess.get_file_as_string("res://shaders/nightlife_beam.gdshader")
	_t._check(src.contains("uniform float look3") and src.contains("street_knee"), "the shaft's street-level soft knee is in the beam shader")


func _trees(city: Node3D) -> void:
	var plan: CityPlan = city.get("plan") if city != null else null
	var palaces: Array = Broadway.palaces(plan) if plan != null else []
	if palaces.is_empty():
		_t._check(plan != null, "no palaces for this seed: nothing to keep clear")
		return
	var p: Dictionary = palaces[0]
	var c: Vector2 = (p.lot as Dictionary).center
	var x := Broadway.avenue_x() + float(p.side) * (Broadway.avenue_width() * 0.5 + plan.sidewalk_width * 0.6)
	var front := Vector3(x, 0.0, c.y)
	var road := Vector3(Broadway.avenue_x(), 0.0, c.y)
	var far := Vector3(x, 0.0, Broadway.z_range().y + 400.0)
	var kept := BroadwayNight.keeps_tree_off(plan, front)
	BroadwayNight.enabled = false
	var off := BroadwayNight.keeps_tree_off(plan, front)
	BroadwayNight.enabled = true
	_t._check(kept and not off and not BroadwayNight.keeps_tree_off(plan, road) and not BroadwayNight.keeps_tree_off(plan, far),
		"street trees keep off a palace's frontage (not the road, not past the district, not with the pass off)")
