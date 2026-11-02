extends RefCounted
## The marine-morning refcam's fixes (wave 5, rc2-marine; MarineMorning), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The hour curve, the damp floor and the coast's mist (pure), the switch, Weather settling the
## streets damp under the deck at 08:00 (and dry in the afternoon and under a clear sky), the deck
## shader's new underside behind its `look` uniform, the camera row in cameras_w5.json.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	_pure()
	_weather(city)
	_shader_and_camera()


func _pure() -> void:
	_t._check(is_equal_approx(MarineMorning.morning(7.0), 1.0) and MarineMorning.morning(12.5) == 0.0
		and MarineMorning.morning(23.5) > 0.99 and MarineMorning.morning(10.75) > 0.0 and MarineMorning.morning(10.75) < 1.0,
		"MarineMorning: the damp and mist run overnight and through the morning, gone by noon, back late at night")
	_t._check(is_equal_approx(MarineMorning.damp(1.0, 8.0), MarineMorning.DAMP) and MarineMorning.damp(0.0, 8.0) == 0.0
		and MarineMorning.damp(1.0, 14.0) == 0.0,
		"MarineMorning: the damp floor is DAMP under a full deck at 08:00, none outside it or in the afternoon")
	_t._check(MarineMorning.DAMP < 0.5, "MarineMorning: the damp is damp, never a shower's soaking (%.2f)" % MarineMorning.DAMP)
	var at_coast := MarineMorning.mist(1.0, 8.0, 100.0)
	var inland := MarineMorning.mist(1.0, 8.0, MarineMorning.COAST_REACH + 50.0)
	_t._check(is_equal_approx(at_coast, MarineMorning.MIST) and inland == 0.0 and MarineMorning.mist(1.0, 13.0, 100.0) == 0.0,
		"MarineMorning: the mist is thick at the coast in the morning, none %d m inland or after noon" % int(MarineMorning.COAST_REACH))
	var was := MarineMorning.enabled
	MarineMorning.enabled = false
	var off := MarineMorning.damp(1.0, 8.0) + MarineMorning.mist(1.0, 8.0, 0.0) + MarineMorning.deck_look()
	MarineMorning.enabled = was
	_t._check(off == 0.0, "MARINE_MORNING=0 turns the damp, the mist and the deck's new underside off")


func _weather(city: Node3D) -> void:
	var weather := city.get_node_or_null("Weather")
	if weather == null or not weather.has_method("settle_wet"):
		_t._check(false, "rc2_marine: the city has a Weather with settle_wet()")
		return
	var keys: Array = weather.get_script().get_script_constant_map().get("STATE_KEYS", [])
	var marine := keys.find("marine")
	var clear := keys.find("clear")
	# The refcam's eye on 11th St, two metres up: under the deck at 08:00, out of it by 14:00.
	var eye := Vector3(-585.0, 2.0, 1205.0)
	weather.call("settle_wet", marine, 8.0, eye)
	var morning_wet := float(weather.get("wetness"))
	var morning_drying := float(weather.get("drying"))
	var morning_mist := float(weather.get("road_mist"))
	weather.call("settle_wet", marine, 14.0, eye)
	var afternoon_wet := float(weather.get("wetness"))
	weather.call("settle_wet", clear, 8.0, eye)
	var clear_wet := float(weather.get("wetness"))
	_t._check(absf(morning_wet - MarineMorning.DAMP) < 0.02 and is_equal_approx(morning_drying, MarineMorning.DRYING),
		"Weather.settle_wet: the beach town is damp (%.2f, drying %.1f) under the deck at 08:00" % [morning_wet, morning_drying])
	_t._check(is_equal_approx(morning_mist, 1.0) and float(weather.get("road_mist")) == 0.0,
		"Weather.settle_wet: the morning damp is the mist's (road_mist 1), none under a clear sky")
	_t._check(afternoon_wet < 0.01 and clear_wet < 0.01,
		"Weather.settle_wet: dry once the deck has burnt off (%.2f) and under a clear sky (%.2f)" % [afternoon_wet, clear_wet])
	# High over the deck there is no mist on the street to make damp.
	weather.call("settle_wet", marine, 8.0, Vector3(eye.x, LaWeather.DECK_TOP + 300.0, eye.z))
	_t._check(float(weather.get("wetness")) < 0.01, "Weather.settle_wet: a camera above the deck reads no damp")
	weather.call("settle_wet", clear, 12.0, eye)
	PropFactory.set_wetness(0.0)


func _shader_and_camera() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/marine_layer.gdshader")
	var road := FileAccess.get_file_as_string("res://shaders/road.gdshader")
	_t._check(road.contains("global uniform float road_mist;") and road.contains("if (road_mist > 0.0)"),
		"road.gdshader: the mist's matte damp sits behind road_mist (0: the rain's street, as before)")
	_t._check(src.contains("uniform float look = 0.0;") and src.contains("if (look > 0.5)"),
		"marine_layer.gdshader: the stratocumulus underside sits behind `look`, 0 by default (the old deck)")
	_t._check(is_equal_approx(MarineMorning.deck_look(), MarineMorning.LOOK if MarineMorning.enabled else 0.0),
		"MarineMorning.deck_look() follows the switch")
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json"))
	var row: Dictionary = {}
	if table is Dictionary:
		for c: Dictionary in table.get("cameras", []):
			if String(c.get("name", "")) == "marine_morning":
				row = c
	_t._check(not row.is_empty() and String(row.get("weather", "")) == "marine" and is_equal_approx(float(row.get("hour", 0.0)), 8.0),
		"cameras_w5.json: the marine_morning camera is 08:00 under the marine layer")
