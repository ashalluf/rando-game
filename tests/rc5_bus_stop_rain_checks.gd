extends RefCounted
## The bus stop in the rain (RainDusk, the bus_stop_rain reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the camera row (18:00, rain, a bus stop at its `bus.at`); RainDusk's weight (0 at noon,
## after dark and in the dry, most of it at a rainy sunset); the sky / fog pulled to slate at their
## own brightness, the cloud to grey, the GOLDEN grade cut; the road's day mirror handed over
## (RainDay.publish's dusk lamps move the mirror, never the after-dark lamp level); the lamp streak
## shader's look5 and its switch; RC5_BUS_STOP=0 puts the old look back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := RainDusk.enabled
	RainDusk.enabled = true
	_pure()
	_mirror()
	_shader()
	_camera(city.plan)
	RainDusk.enabled = false
	_t._check(RainDusk.weight(0.5, 1.0, 1.0, 0.0) == 0.0 and RainDusk.mirror_lamps(RainDusk.weight(0.5, 1.0, 1.0, 0.0)) == 0.0,
		"RC5_BUS_STOP=0: no rainy-dusk weight, the road's mirror as before")
	RainDusk.enabled = was


func _pure() -> void:
	var dusk := RainDusk.weight(0.5, 1.0, 1.0, 0.04)
	_t._check(dusk > 0.7, "rain dusk: a rainy sunset is weighted (%.2f)" % dusk)
	_t._check(RainDusk.weight(0.5, 0.0, 0.0, 0.0) == 0.0 and RainDusk.weight(0.5, 0.3, 0.0, 1.0) == 0.0
		and RainDusk.weight(0.0, 1.0, 1.0, 0.0) == 0.0,
		"rain dusk: nothing at noon, after dark or in the dry (noon rain, rainy nights, clear sunsets bit for bit)")
	var peach := Color(0.631, 0.444, 0.355)
	var s := RainDusk.sky(peach, dusk)
	var l0 := peach.r * 0.2126 + peach.g * 0.7152 + peach.b * 0.0722
	var l1 := s.r * 0.2126 + s.g * 0.7152 + s.b * 0.0722
	_t._check(s.b > s.r and absf(l1 - l0) < 0.08,
		"rain dusk: the peach horizon goes slate at its own brightness (%s, luma %.3f -> %.3f)" % [str(s), l0, l1])
	var c := RainDusk.cloud(Color(1.0, 0.72, 0.5), dusk)
	_t._check(c.b > 0.8 and c.r - c.b < 0.15, "rain dusk: the deck is grey, not dusk_cloud orange (%s)" % str(c))
	_t._check(RainDusk.golden(1.0, dusk) < 0.4 and RainDusk.golden(1.0, 0.0) == 1.0,
		"rain dusk: the GOLDEN grade is cut under the deck (%.2f), whole without it" % RainDusk.golden(1.0, dusk))
	_t._check(RainDusk.fog(Color(0.49, 0.44, 0.44), 0.0) == Color(0.49, 0.44, 0.44), "rain dusk: the fog untouched at weight 0")


func _mirror() -> void:
	var was_lamp := RainDay.night_lamp
	RainDay.publish(0.1, 0.0)
	var plain := RainDay.day_weight(maxf(0.1, 0.0))
	RainDay.publish(0.1, RainDusk.mirror_lamps(0.8))
	_t._check(RainDay.night_lamp == 0.1 and RainDay.day_weight(maxf(0.1, RainDusk.mirror_lamps(0.8))) < plain - 0.5,
		"rain dusk: the road's day mirror hands over to the lit city's (%.2f -> %.2f), the after-dark lamp level kept" % [plain,
			RainDay.day_weight(maxf(0.1, RainDusk.mirror_lamps(0.8)))])
	RainDay.publish(was_lamp, 0.0)


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/night_wet.gdshader")
	_t._check(src.contains("uniform float look5 = 0.0;") and src.contains("if (look5 > 0.5)"),
		"rain dusk: night_wet carries look5 (fine sparkle, off by default)")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/night_wet.gdshader")
	RainStreetNight.dress_wet(m)
	_t._check(float(m.get_shader_parameter("look5")) == 1.0, "rain dusk: the lamp streak material wears look5")


func _camera(plan: CityPlan) -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var row: Dictionary = {}
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for c: Dictionary in d.get("cameras", []):
				if String(c.get("name", "")) == "bus_stop_rain":
					row = c
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 18.0 and String(row.get("weather", "")) == "rain"
		and String(row.get("stage", "")) == "bus" and row.get("bus", null) is Dictionary,
		"rain dusk: the bus_stop_rain camera row (18:00, rain, a staged bus)")
	if row.is_empty() or not row.get("bus", null) is Dictionary:
		return
	var at: Array = row.bus.at
	var p := Vector2(float(at[0]), float(at[1]))
	var bi := plan.block_index_at(p)
	var found := false
	for index in range(bi.y - 2, bi.y + 3):
		if absf(plan.road_pos(CityPlan.AXIS_Z, index) - p.y) > 1.0:
			continue
		for k in range(bi.x - 2, bi.x + 3):
			var stop := BigVehicles.block_stop(plan, CityPlan.AXIS_Z, index, k, int(row.bus.get("dir", 1)))
			if not is_nan(stop) and absf(stop - p.x) < 1.0:
				found = true
	_t._check(found, "rain dusk: the row's bus.at is a real stop of a bus line (%s)" % str(p))
	var eye: Array = row.eye
	_t._check(Vector2(float(eye[0]), float(eye[2])).distance_to(p) < 25.0, "rain dusk: the eye stands by the stop")
