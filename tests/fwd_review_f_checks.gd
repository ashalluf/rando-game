extends RefCounted
## Forward+ review f (fleet wave 4, session fwd-review-f), for tests/smoke_test.gd: wave 3's
## batches 21-25 looked at on lavapipe Forward+ against opengl3 (docs/HANDOFF.md "Forward+ review
## f"). One fix held here: a lightning strike at night whited out the whole frame on both
## renderers (the day's flash against the night exposure) and on Forward+ also lit the
## rain-thickened volumetric fog into a veil. StormDrama.night_flash_gain() scales the flash's
## light and the sky's flash by moonlight; the bolt keeps the whole flicker; the lightning light's
## volumetric-fog energy is FLASH_FOG_ENERGY. Source text and statics only, plus the city's own
## Weather node when there is one.

var _t: Node


func _code(p: String) -> String:
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(p).split("\n"):
		lines.append(line.split("##")[0].split("# ")[0])
	return "\n".join(lines)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_t._check(StormDrama.night_flash_on, "fwd-review-f: the night flash scaling is on (STORM_NIGHT_FLASH unset)")
	_t._check(is_equal_approx(StormDrama.night_flash_gain(0.0), 1.0) and is_equal_approx(StormDrama.night_flash_gain(0.0, true), 1.0),
		"a strike by day keeps the whole flash, light and sky")
	var light_n := StormDrama.night_flash_gain(1.0)
	var sky_n := StormDrama.night_flash_gain(1.0, true)
	_t._check(light_n > 0.1 and light_n < 0.4 and sky_n > light_n and sky_n < 0.7,
		"at night the flash's light is cut to %.2f and the sky's flash to %.2f" % [light_n, sky_n])
	var mid := StormDrama.night_flash_gain(0.5)
	_t._check(mid < 1.0 and mid > light_n, "the cut eases in with the moonlight (%.2f at half)" % mid)
	_t._check(StormDrama.flash_fog_energy() < 0.5, "the lightning light lights the volumetric fog at %.2f, not Godot's 1.0" % StormDrama.flash_fog_energy())
	# The switch off gives the old numbers back.
	StormDrama.night_flash_on = false
	var off_ok := is_equal_approx(StormDrama.night_flash_gain(1.0), 1.0) and is_equal_approx(StormDrama.flash_fog_energy(), 1.0)
	StormDrama.night_flash_on = true
	_t._check(off_ok, "STORM_NIGHT_FLASH=0 puts the full flash and fog energy back")
	var w := _code("res://scripts/world/weather.gd")
	_t._check(w.contains("_drama.on_flash(flash, _sky, _strike_dir)"), "the bolt still gets the whole flicker (on_flash unscaled)")
	_t._check(w.contains("flash_light_energy * StormDrama.night_flash_gain(moon)")
		and w.contains("\"weather_flash\", flash * StormDrama.night_flash_gain(moon)")
		and w.contains("\"flash\", flash * StormDrama.night_flash_gain(moon, true)"),
		"the lightning light, the sun's flash term and the sky's flash all take the night cut")
	var weather: Node = city.get_node_or_null("Weather") if city else null
	if weather:
		var fl: DirectionalLight3D = weather.get("_flash_light")
		_t._check(fl != null and is_equal_approx(fl.light_volumetric_fog_energy, StormDrama.FLASH_FOG_ENERGY),
			"the city's lightning light carries the trimmed fog energy")
