extends RefCounted
## The gas station at night (GasNight, wave 8 refcam gas_station_night), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the camera row; the forecourt's UV2 code round-trips (half size, quarter turn) the way
## roadside.gdshader decodes it, and the shader carries the canopy light; the canopy omni reaches
## the whole canopy; a FULL gas station built with PUMP_CAR forced has an empty car beside a
## dispenser and its driver standing at the pump, and with GasNight off neither.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_camera_row()
	_encoding()
	_night_ground()
	var e := _find_gas(city, plan)
	_t._check(not e.is_empty(), "a gas station was found round the spawn for the GasNight checks")
	if e.is_empty():
		return
	var budget := t.get_node("/root/PhysicsBudget")
	var cap: int = budget.max_active_bodies
	budget.max_active_bodies = 1 << 30
	var keep_force := GasNight.force_pump_car
	GasNight.force_pump_car = true
	_full(city, e, true)
	GasNight.enabled = false
	_full(city, e, false)
	GasNight.enabled = true
	GasNight.force_pump_car = keep_force
	budget.max_active_bodies = cap


func _camera_row() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in (parsed as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "gas_station_night":
				row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 23.5) and String(row.get("weather", "")) == "clear"
		and int(row.get("pump_car", 0)) == 1, "the gas_station_night refcam row is in cameras_w8.json (23:30 clear, a car at a pump)")


## The forecourt's UV2 as roadside.gdshader's gas_forecourt() reads it back.
func _encoding() -> void:
	var ok := true
	for q in 4:
		for size: Vector2 in [Vector2(13.0, 6.0), Vector2(27.0, 14.0), Vector2(19.4, 9.7)]:
			var u2 := GasNight.forecourt_u2(q * PI * 0.5 + (TAU if q == 3 else 0.0), size.x, size.y)
			var hx := u2.x - 100.0
			var qq := floorf((u2.y + 50.0) / 100.0)
			var hz := u2.y - 100.0 * qq
			ok = ok and u2.x > 50.0 and is_equal_approx(hx, size.x * 0.5) and is_equal_approx(hz, size.y * 0.5) and int(qq) == q
	_t._check(ok, "the forecourt's UV2 carries the canopy's half size and quarter turn, decoded as the shader does")
	var src := FileAccess.get_file_as_string("res://shaders/roadside.gdshader")
	_t._check(src.contains("vec3 gas_forecourt(") and src.contains("uniform float forecourt_light") and src.contains("UV2.x > 50.0"),
		"roadside.gdshader lights and mirrors the forecourt from the canopy's panels (gas_forecourt)")
	var spot: Array = GasNight.light_spot(Vector2.ZERO, 27.0, 14.0, 4.9)
	_t._check(float(spot[1]) >= Vector2(13.5, 7.0).length() + 4.0 and (spot[0] as Vector3).y < 4.9,
		"the canopy's omni reaches past the canopy's corners (%.1f m) from under its soffit" % float(spot[1]))


## NightGround: a street lamp's omni is a point source over twice its height, its light under the
## head as before; the compat pool takes a share; the switch puts NightLamps' numbers back.
func _night_ground() -> void:
	var a := OmniLight3D.new()
	a.omni_range = 16.0
	a.omni_attenuation = 1.1
	NightLamps.tune_light(a, 8.0)
	var under := float(a.get_meta("lamp_gain", 1.0)) * pow(8.0, -a.omni_attenuation)
	var between := float(a.get_meta("lamp_gain", 1.0)) * pow(8.0 * 1.7, -a.omni_attenuation)
	var keep := NightGround.enabled
	NightGround.enabled = false
	var b := OmniLight3D.new()
	b.omni_range = 16.0
	b.omni_attenuation = 1.1
	NightLamps.tune_light(b, 8.0)
	var under_old := float(b.get_meta("lamp_gain", 1.0)) * pow(8.0, -b.omni_attenuation)
	var between_old := float(b.get_meta("lamp_gain", 1.0)) * pow(8.0 * 1.7, -b.omni_attenuation)
	NightGround.enabled = keep
	_t._check(not NightLamps.enabled or (is_equal_approx(a.omni_attenuation, NightLamps.POINT_FALLOFF) and is_equal_approx(a.omni_range, NightLamps.POINT_REACH_PER_HEIGHT * 8.0)
		and absf(under / under_old - 1.0) < 0.01 and between < between_old * 0.85 and is_equal_approx(b.omni_attenuation, NightLamps.FALLOFF) and is_equal_approx(b.omni_range, NightLamps.REACH_PER_HEIGHT * 8.0)),
		"NightGround: a street lamp's light under its head is unchanged (%.3f / %.3f) and darker between lamps (%.3f / %.3f)" % [under, under_old, between, between_old])
	a.free()
	b.free()
	var pool := PropFactory.light_pool()
	var mat := (pool as QuadMesh).material as ShaderMaterial
	_t._check(is_equal_approx(float(mat.get_shader_parameter("street_compat")), NightGround.pool_compat()) and NightGround.pool_compat() < 1.0,
		"NightGround: a street lamp's pool adds %.2f of itself on Compatibility (the omni lights the rest)" % float(mat.get_shader_parameter("street_compat")))
	var src := FileAccess.get_file_as_string("res://shaders/light_pool.gdshader")
	_t._check(src.contains("ALPHA *= street_compat;"), "light_pool.gdshader takes street_compat on Compatibility")


func _find_gas(city: Node3D, plan: CityPlan) -> Dictionary:
	Roadside.recording = true
	Roadside.record.clear()
	var k0: Vector2i = plan.block_index_at(Vector2.ZERO)
	var found := {}
	for r in 7:
		for bx in range(k0.x - r, k0.x + r + 1):
			for bz in range(k0.y - r, k0.y + r + 1):
				if maxi(absi(bx - k0.x), absi(bz - k0.y)) != r or not found.is_empty():
					continue
				var before := Roadside.record.size()
				var cap := CityChunk.new()
				cap.plan = plan
				cap.ix = bx
				cap.iz = bz
				cap.level = CityChunk.Level.LOD
				cap.style = city.chunk_style()
				cap.capturing = true
				cap.build()
				cap.free()
				for i in range(before, Roadside.record.size()):
					var e: Dictionary = Roadside.record[i]
					if int(e.kind) == Roadside.Kind.GAS and found.is_empty():
						found = e
	Roadside.recording = false
	Roadside.record.clear()
	return found


func _full(city: Node3D, e: Dictionary, on: bool) -> void:
	var cars0 := int(GasNight.stats.cars)
	var chunk: CityChunk = city._new_chunk(e.block, CityChunk.Level.FULL)
	chunk.build()
	var c: Vector2 = e.centre
	var ws := _t.get_node("/root/WorldState")
	var car: Node3D = null
	for v in chunk.get("_cars"):
		if is_instance_valid(v) and (v as Node).has_meta("pump_car"):
			car = v
	var person: Node3D = null
	for p in chunk.get_children():
		if (p as Node).is_in_group("gas_customer"):
			person = p
	if on:
		# The car lives under the city root (local = true world less the offset), the person under
		# the chunk (local = true world).
		var car_w: Vector3 = ws.to_world(car.position) if car else Vector3.INF
		var car_xz := Vector2(car_w.x, car_w.z)
		var near := car != null and car_xz.distance_to(c) < maxf(float(e.w), float(e.d))
		_t._check(near and int(GasNight.stats.cars) > cars0 and car.get("driver") == null and not bool(car.get("_npc_driver")),
			"a gas station with PUMP_CAR forced has an empty car parked on its forecourt (%s, pad at %s)" % [str(car_xz), str(c)])
		var dist := INF
		if person and car:
			dist = Vector2(person.position.x, person.position.z).distance_to(car_xz)
		_t._check(person != null and person is StreetVendor and dist < 3.2,
			"its driver stands at the pump beside it (%.1f m from the car)" % dist)
	else:
		_t._check(car == null and person == null, "with GAS_NIGHT=0 no car or customer is added at the pumps")
	chunk.retire()
	chunk.queue_free()
