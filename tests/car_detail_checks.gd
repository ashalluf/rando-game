extends RefCounted
## The close-up detail of a car (CarDetail, scripts/vehicles/car_detail.gd) for
## tests/smoke_test.gd. Loaded at run time, so it can name Vehicle, CarDetail and PropFactory.
## Builds its own cars high over the city and frees them; nothing leans on where an earlier check
## left the player or the traffic. Checks: the plate text is the car's own, in the invented
## format, and stable; the grime levels are pure and spread over the fleet (work trucks dirtier,
## the beater never clean); the tyre text reads the wheel's own size; a car builds its plates and
## badges only when it comes near, as ONE shadowless mesh on the shared pair of materials, drawn
## only in the body's near range, the rear plate on the tail and the front on the nose; its own
## paint material carries the grime (no material added); wheels of one kit and dust level share
## one material; the near wheel carries raised sidewall lettering; the lamps switch the plate
## lamp; random_car() spends the caller's rng exactly as before; CAR_DETAIL off (the A/B) builds
## the car exactly as it was.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _cars: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var was := CarDetail.enabled
	CarDetail.enabled = true
	_pure()
	await _car_build()
	await _ab()
	_rng()
	_shaders()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	CarDetail.enabled = was


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _pure() -> void:
	var re := RegEx.create_from_string("^[A-HJ-NP-Z]{2}[0-9]-[0-9]{3}$")
	var seen := {}
	var fmt := true
	var bad := ""
	for i in 200:
		var p := CarDetail.plate_text(i * 7919 + 13)
		if re.search(p) == null:
			fmt = false
			bad = p
		seen[p] = true
	_check(fmt, "every plate is two letters (no I, O, Q), a digit, a dash and three digits%s" % ("" if fmt else " (%s)" % bad))
	_check(seen.size() >= 195, "plates differ car to car (%d of 200 distinct)" % seen.size())
	_check(CarDetail.plate_text(4242) == CarDetail.plate_text(4242), "a car's plate is the same every time")
	# Grime over the fleet.
	var clean := 0
	var beater_clean := 0
	var work_clean := 0
	var ranged := true
	for i in 400:
		var g := CarDetail.grime_for(Vehicle.BodyType.SEDAN, i * 104729)
		if float(g[0]) == 0.0:
			clean += 1
		ranged = ranged and float(g[0]) >= 0.0 and float(g[0]) <= 1.0 and int(g[3]) >= 0 and int(g[3]) <= 2
		if float(CarDetail.grime_for(Vehicle.BodyType.BEATER, i * 104729)[0]) < 0.3:
			beater_clean += 1
		if float(CarDetail.grime_for(Vehicle.BodyType.PICKUP, i * 104729)[0]) == 0.0:
			work_clean += 1
	_check(ranged, "grime levels stay in range (grime 0..1, wheel dust 0..2)")
	_check(clean > 80 and clean < 220, "about a third of the sedans are clean (%d of 400)" % clean)
	_check(beater_clean == 0 and work_clean == 0, "the beater and the work trucks are never clean (%d, %d)" % [beater_clean, work_clean])
	_check(CarDetail.grime_for(Vehicle.BodyType.SUV, 777) == CarDetail.grime_for(Vehicle.BodyType.SUV, 777), "grime is a pure function of the car's look")
	var tt := CarDetail.tyre_text(0, 0.345, 0.345 * 0.735, 0.235)
	_check(String(tt[2]).begins_with("235/") and String(tt[2]).contains("R20"),
			"the sidewall's size reads the wheel's own width and rim (%s)" % tt[2])
	_check(not CarDetail.TYRE_MAKERS.has(""), "the tyre makers are named")


func _car(type: int, x: float, look: int) -> Vehicle:
	var car := Vehicle.new()
	car.body_type = type
	car.look_seed = look
	_city.add_child(car)
	var player := _tree.get_first_node_in_group("player") as Node3D
	car.global_position = player.global_position + Vector3(x, 400.0, 30.0)
	_cars.append(car)
	return car


func _car_build() -> void:
	var car := _car(Vehicle.BodyType.SEDAN, -10.0, 31337)
	_check(car.has_meta("car_detail") and car.get_node_or_null("CarDetail") == null,
			"a new car waits for its plates until it comes near")
	CarDetail.near(car)
	CarDetail.flush()
	var mi := car.get_node_or_null("CarDetail") as MeshInstance3D
	_check(mi != null and mi.mesh != null and mi.mesh.get_surface_count() == 1,
			"near, the plates and badges are one mesh of one surface")
	if mi == null or mi.mesh == null:
		return
	_check(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and is_equal_approx(mi.visibility_range_end, car.body_far_distance),
			"it casts no shadow and draws only in the body's near range (%.0f m)" % mi.visibility_range_end)
	_check(mi.material_override == CarDetail.material(false) or mi.material_override == CarDetail.material(true),
			"it wears the shared detail material")
	var faces := mi.mesh.get_faces()
	var box := AABB(faces[0], Vector3.ZERO) if faces.size() > 0 else AABB()
	var front := 0
	var rear := 0
	for p in faces:
		box = box.expand(p)
		if p.z > float(car._dims().length) * 0.35:
			rear += 1
		elif p.z < -float(car._dims().length) * 0.35:
			front += 1
	var d := car._dims()
	_check(faces.size() / 3 < 4000 and faces.size() > 300, "a car's plates and badges are a few thousand triangles at most (%d)" % (faces.size() / 3))
	_check(box.size.x < float(d.width) and absf(box.position.z) < float(d.length) * 0.5 + 0.12 and absf(box.end.z) < float(d.length) * 0.5 + 0.12,
			"they stay on the body (box %s)" % box)
	_check(front > 100 and rear > 100, "a plate on the nose and one on the tail (%d / %d vertices)" % [front, rear])
	var mats := CarDetail.paint_materials(car)
	var g := CarDetail.grime_for(car.body_type, CarDetail.look_of(car))
	var set_ok := not mats.is_empty()
	for m in mats:
		set_ok = set_ok and is_equal_approx(float(m.get_shader_parameter("grime")), float(g[0])) \
				and is_equal_approx(float(m.get_shader_parameter("mud")), float(g[1]))
	_check(set_ok and mats.size() == 1, "the car's own paint material carries its grime (%d paint material)" % mats.size())
	CarDetail.lamps(car, true)
	var lit := mi.material_override == CarDetail.material(true)
	CarDetail.lamps(car, false)
	_check(lit and mi.material_override == CarDetail.material(false), "the tail lamps switch the plate lamp")
	# Wheels: one material per kit and dust level, shared.
	var a := _car(Vehicle.BodyType.SEDAN, 0.0, 1)
	var b := _car(Vehicle.BodyType.SEDAN, 10.0, 1)
	await _tree.process_frame
	var ma: Material = (a._wheel_rigs[0][1] as MeshInstance3D).material_override if not a._wheel_rigs.is_empty() else null
	var mb: Material = (b._wheel_rigs[0][1] as MeshInstance3D).material_override if not b._wheel_rigs.is_empty() else null
	_check(ma != null and ma == mb, "two cars of the same kit and dust share one wheel material")
	var near_mesh := PropFactory.car_wheel(0, 0.345, 0.235, true)
	CarDetail.enabled = false
	var plain := PropFactory.car_wheel(0, 0.345, 0.235, true)
	CarDetail.enabled = true
	var lettered := near_mesh.get_faces().size() / 3 - plain.get_faces().size() / 3
	_check(lettered > 200 and lettered < 4000, "the near wheel carries raised sidewall lettering (+%d triangles)" % lettered)
	var far_l := PropFactory.car_wheel(0, 0.345, 0.235, false)
	CarDetail.enabled = false
	var far_p := PropFactory.car_wheel(0, 0.345, 0.235, false)
	CarDetail.enabled = true
	_check(far_l == far_p, "the far wheel is untouched")


func _ab() -> void:
	CarDetail.enabled = false
	var car := _car(Vehicle.BodyType.SEDAN, 20.0, 31337)
	CarDetail.near(car)
	CarDetail.flush()
	var mats := CarDetail.paint_materials(car)
	var clean := not mats.is_empty()
	for m in mats:
		var gv: Variant = m.get_shader_parameter("grime")
		var mv: Variant = m.get_shader_parameter("mud")
		clean = clean and (gv == null or float(gv) == 0.0) and (mv == null or float(mv) == 0.0)
	var wheel_plain := car._wheel_rigs.is_empty() or (car._wheel_rigs[0][1] as MeshInstance3D).material_override == PropFactory.wheel_material(car.wheel_kit)
	CarDetail.enabled = true
	_check(car.get_node_or_null("CarDetail") == null and not car.has_meta("car_detail") and clean and wheel_plain,
			"CAR_DETAIL off builds the car as it was: no plates, clean paint, plain wheels")
	await _tree.process_frame


func _rng() -> void:
	var r1 := RandomNumberGenerator.new()
	r1.seed = 99
	var c1 := Vehicle.random_car(r1)
	CarDetail.enabled = false
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	var c2 := Vehicle.random_car(r2)
	CarDetail.enabled = true
	_check(r1.state == r2.state and c1.body_type == c2.body_type and c1.paint == c2.paint,
			"random_car() spends the caller's rng exactly as it did without the detail")
	c1.free()
	c2.free()


func _shaders() -> void:
	var paint: Shader = load("res://shaders/car_paint.gdshader")
	var names := []
	for u in paint.get_shader_uniform_list():
		names.append(String(u.name))
	_check(names.has("grime") and names.has("mud") and names.has("scratches") and names.has("grime_arch"),
			"car_paint has the grime uniforms")
	var glass: Shader = load("res://shaders/car_glass.gdshader")
	var gn := []
	for u in glass.get_shader_uniform_list():
		gn.append(String(u.name))
	_check(gn.has("screen_dust"), "the cabin glass has the windscreen's dust")
	var det: Shader = load("res://shaders/car_detail.gdshader")
	_check(det.get_shader_uniform_list().size() >= 2, "car_detail.gdshader compiles")
