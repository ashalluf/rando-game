extends RefCounted
## The marine layer's evening bank from the beach (MarineEvening, the marine_evening reference camera
## in tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks: the camera row (18:30, marine, on the sand, the bank ~1.6 km offshore and low); the
## leavers' hours; the twilight shadows (full by day and deep night, soft at 18:30); the rim colour;
## the bank shader's wall branch and its sunk foot; the bank drawn after the deck planes; a beach
## walker that leaves heads up the sand; MARINE_EVENING=0 puts the old look back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := MarineEvening.enabled
	MarineEvening.enabled = true
	_pure()
	_shader()
	_camera(city.plan)
	_walker(city.plan)
	MarineEvening.enabled = false
	_t._check(MarineEvening.bank_look() == 0.0 and MarineEvening.leavers(18.5, 0.2) == 0
		and MarineEvening.twilight_shadow(-0.13, 0.38) == 1.0,
		"MARINE_EVENING=0: the old bank, no leavers, the moon's shadows as they were")
	MarineEvening.enabled = was


func _elev(h: float) -> float:
	return sin((h - 6.0) / 12.0 * PI)


func _moon(e: float) -> float:
	return smoothstep(0.02, -0.34, e)


func _pure() -> void:
	_t._check(MarineEvening.leavers(18.5, 0.16) >= 4 and MarineEvening.leavers(14.0, 1.0) == 0
		and MarineEvening.leavers(21.0, 0.0) == 0 and MarineEvening.leavers(18.5, 0.0) > 0,
		"marine evening: people leave the beach at 18:30 (%d a stretch), none at 14:00 or 21:00" % MarineEvening.leavers(18.5, 0.16))
	var noon := MarineEvening.twilight_shadow(_elev(12.0), _moon(_elev(12.0)))
	var dusk := MarineEvening.twilight_shadow(_elev(18.5), _moon(_elev(18.5)))
	var night := MarineEvening.twilight_shadow(_elev(22.0), _moon(_elev(22.0)))
	var golden := MarineEvening.twilight_shadow(_elev(17.5), _moon(_elev(17.5)))
	_t._check(noon == 1.0 and golden == 1.0 and night == 1.0 and dusk < 0.4,
		"twilight shadows: full at noon, at 17:30 and at 22:00, soft at 18:30 (%.2f)" % dusk)
	var rim := MarineEvening.rim(Color(0.5, 0.35, 0.4), Color(1.0, 0.6, 0.4), 0.0)
	var rim_n := MarineEvening.rim(Color(0.5, 0.35, 0.4), Color(1.0, 0.6, 0.4), 1.0)
	_t._check(rim.r > rim.b and rim.r > 0.5 and rim_n.r < 0.05,
		"the bank's crest glows warm in the afterglow (%s), dark at night" % rim)


func _shader() -> void:
	var s := FileAccess.get_file_as_string("res://shaders/marine_layer.gdshader")
	_t._check(s.contains("uniform float bank_look") and s.contains("mode == 2 && bank_look > 0.5")
		and s.contains("- 8.0 * (1.0 - h01)") and s.contains("rim_col"),
		"the bank shader: the wall branch, its foot sunk under the water, the afterglow rim")
	var w := FileAccess.get_file_as_string("res://scripts/world/weather.gd")
	var d := FileAccess.get_file_as_string("res://scripts/world/day_night.gd")
	var b := FileAccess.get_file_as_string("res://scripts/world/beach_life.gd")
	_t._check(w.contains("MarineEvening.rim(") and d.contains("MarineEvening.twilight_shadow(")
		and b.contains("MarineEvening.add_leavers("), "Weather, DayNight and BeachLife carry the hooks")
	var ml := MarineLayer.new()
	ml._ready()
	_t._check(ml._mats.size() == 3 and ml._mats[2].render_priority > ml._mats[0].render_priority
		and ml._mats[2].render_priority > ml._mats[1].render_priority,
		"the bank is drawn after the deck planes (it stands in front of them from the shore)")
	ml.free()


func _row() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	if not data is Dictionary:
		return {}
	for c: Dictionary in data.get("cameras", []):
		if c.name == "marine_evening":
			return c
	return {}


func _camera(plan: CityPlan) -> void:
	var row := _row()
	if row.is_empty():
		_t._check(false, "the marine_evening camera row is in cameras_w8.json")
		return
	var eye: Array = row.eye
	var x := float(eye[0])
	var z := float(eye[2])
	var coast := plan.macro.coast_x(z)
	var on_sand := x > coast and x < coast + plan.macro.beach_width_at(z)
	var edge := LaWeather.edge_offset(float(row.hour))
	var deck := LaWeather.deck_heights(float(row.hour))
	_t._check(on_sand and String(row.weather) == "marine" and absf(float(row.hour) - 18.5) < 0.01
		and edge < -1000.0 and edge > -2200.0 and absf(deck.y - LaWeather.BANK_TOP) < 1.0,
		"marine_evening: 18:30 marine, the eye on the sand, the bank %.0f m offshore and low" % -edge)


func _walker(plan: CityPlan) -> void:
	var w := BeachWalker.new()
	w.plan_ref = plan
	w.leaving = true
	w.z_lo = 790.0
	w.z_hi = 850.0
	w.setup(Rect2(-760.0, 790.0, 100.0, 60.0), 4.0, 77)
	var macro: MacroMap = plan.macro
	w.position = Vector3(macro.coast_x(820.0) + 6.0, 1.0, 820.0)
	var up := w._random_ring_point(4.0)
	var back := macro.coast_x(up.y) + macro.beach_width_at(up.y) * 0.8
	_t._check(up.x > back and up.y >= w.z_lo and up.y <= w.z_hi,
		"a leaver walks up to the back of the sand (%.0f past %.0f)" % [up.x, back])
	w.free()
