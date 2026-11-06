extends RefCounted
## The night street review (NightStreetReview, docs/HANDOFF.md "The night street at eye level"),
## for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Pins the tuned numbers (the moon well under the lamps, the pools and ranges, Broadway's lantern
## gain, the rain's night fill) and the switch that puts them back; the mirrors' sky following the
## weather; a street lamp placed the same with the review on and off but for its pool and range (no
## roll moved); the wet reflection instance only in FULL chunks and only with the review on, keyed
## as the lamp's light; the shaders' tunables and their colour handling; and DayNight handing a
## lamp_gain light its share of the level. Stages what it needs and puts it back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := NightStreetReview.enabled
	var atmos_was := NightAtmos.enabled
	NightStreetReview.enabled = true
	NightAtmos.enabled = true
	_numbers(city)
	_sky()
	_lamps(city)
	_reflection()
	_shaders()
	_lamp_gain(city)
	NightStreetReview.enabled = was
	NightAtmos.enabled = atmos_was


func _numbers(city: Node3D) -> void:
	var R := NightStreetReview
	_t._check(R.moon() == R.MOON and R.MOON >= 0.07 and R.MOON <= 0.12 and R.MOON < R.MOON_OLD,
		"night street: the moon's key %.2f (was %.2f)" % [R.MOON, R.MOON_OLD])
	var day: Node = city.get_node_or_null("DayNight")
	if day:
		var moon_key: float = float(day.get("night_sun_energy")) * float(day.get("night_exposure"))
		var sun_key: float = float(day.get("day_sun_energy")) * float(day.get("day_exposure"))
		_t._check(moon_key < 0.25 * sun_key,
			"night street: the moon through the night exposure is under a quarter of the noon sun (%.2f of %.2f)" % [moon_key, sun_key])
	_t._check(is_equal_approx(R.pool_scale(), 1.3) and is_equal_approx(R.range_scale(), 1.25) and is_equal_approx(R.broadway_light(), 0.6),
		"night street: lamp pools x%.2f, ranges x%.2f, Broadway's lanterns at %.2f" % [R.pool_scale(), R.range_scale(), R.broadway_light()])
	_t._check(R.rain_night_cut() > 0.0 and R.rain_night_cut() <= 0.4, "night street: a rainy night keeps most of its fill (%.2f of the cut)" % R.rain_night_cut())
	R.enabled = false
	_t._check(R.moon() == R.MOON_OLD and R.pool_scale() == 1.0 and R.range_scale() == 1.0 and R.broadway_light() == 1.0 and R.rain_night_cut() == 1.0,
		"night street: NIGHT_STREET_REVIEW=0 puts the old numbers back")
	R.enabled = true


func _sky() -> void:
	var clear := Color(0.07, 0.09, 0.19)
	var storm := Color(0.12, 0.1, 0.1)
	_t._check(NightStreetReview.sky_tint(clear, storm, 1.0).is_equal_approx(storm) and NightStreetReview.sky_tint(clear, storm, 0.0).is_equal_approx(clear),
		"night street: the mirrors' sky is the storm's horizon under rain and the clear one without")
	NightStreetReview.enabled = false
	_t._check(NightStreetReview.sky_tint(clear, storm, 1.0).is_equal_approx(clear), "night street: off, the mirrors keep the clear horizon")
	NightStreetReview.enabled = true


func _lamps(city: Node3D) -> void:
	var plan = city.get("plan")
	if plan == null:
		_t._check(false, "night street: the city has a plan")
		return
	var at := Vector3(2984.0, 0.0, 170.0)
	var on: Dictionary = StreetLamps.place(plan, at, Vector2(1.0, 0.0))
	NightStreetReview.enabled = false
	var off: Dictionary = StreetLamps.place(plan, at, Vector2(1.0, 0.0))
	NightStreetReview.enabled = true
	var spec: Dictionary = StreetLamps.TYPES[int(on.type)]
	_t._check(on.type == off.type and on.xform == off.xform and on.custom == off.custom and on.paint == off.paint,
		"night street: a lamp's type, place, paint and roll are the same with the review on and off")
	_t._check(is_equal_approx(float(on.pool), float(spec.pool) * 1.3) and is_equal_approx(float(off.pool), float(spec.pool))
		and is_equal_approx(float(on.range), float(spec.range) * 1.25),
		"night street: the pool %.1f m (was %.1f) and the range %.1f m" % [float(on.pool), float(off.pool), float(on.range)])


func _reflection() -> void:
	_t._check(NightAtmos.WET_KEY.contains("glow"), "night street: the wet reflection is keyed as the lamp's light (PropBreak's glow word)")
	var lights: Array = [Vector3(0.0, 8.6, 0.0)]
	var full: Array = NightAtmos.lamp_parts(lights, Vector3(0.0, 8.6, 0.0), 0.0, 12.0, Vector2(2984.0, 170.0), true)
	var lod: Array = NightAtmos.lamp_parts(lights, Vector3(0.0, 8.6, 0.0), 0.0, 12.0, Vector2(2984.0, 170.0), false)
	var wet: Array = full.filter(func(p: Array) -> bool: return p[0] == NightAtmos.WET_KEY)
	_t._check(wet.size() == 1 and lod.filter(func(p: Array) -> bool: return p[0] == NightAtmos.WET_KEY).is_empty(),
		"night street: one wet reflection per FULL lamp, none in LOD chunks")
	if wet.size() == 1:
		var xf: Transform3D = wet[0][2]
		var c: Color = wet[0][4]
		_t._check(is_equal_approx(xf.basis.y.length(), 8.6) and is_equal_approx(xf.origin.y, 0.0) and c.r > 0.0 and c.r <= NightAtmos.WET_MAX,
			"night street: the reflection stands at the lamp's foot with the head's height in its basis (%.1f m, strength %.2f)" % [xf.basis.y.length(), c.r])
		var m: Mesh = wet[0][1]
		_t._check(m is ArrayMesh and (m as ArrayMesh).custom_aabb.size.x >= 60.0, "night street: the reflection quad's bounds cover the streak the shader lays")
	var three: Array = NightAtmos.lamp_parts([Vector3.ONE, Vector3.ONE, Vector3.ONE], Vector3(0.0, 5.0, 0.0), 0.0, 10.0, Vector2.ZERO, true)
	for p: Array in three:
		if p[0] == NightAtmos.WET_KEY:
			_t._check((p[4] as Color).r <= NightAtmos.WET_MAX, "night street: a three-globe lamp's reflection is capped")
	NightStreetReview.enabled = false
	var old: Array = NightAtmos.lamp_parts(lights, Vector3(0.0, 8.6, 0.0), 0.0, 12.0, Vector2(2984.0, 170.0), true)
	NightStreetReview.enabled = true
	_t._check(old.size() == full.size() - 1, "night street: off, the lamp keeps its halo and shaft and no reflection")
	var bw := FileAccess.get_file_as_string("res://scripts/world/broadway_street.gd")
	_t._check(bw.contains("ch._night_atmos(globes") and bw.contains("lamp_gain"), "night street: Broadway's lanterns wear halos and a reflection, their light at its share")


func _shaders() -> void:
	var wet := FileAccess.get_file_as_string("res://shaders/night_wet.gdshader")
	_t._check(wet.contains("global uniform float road_wetness;") and wet.contains("VERTEX = vec3(0.0);") and wet.contains("blend_add")
		and wet.contains("cs_srgb_to_linear(COLOR.rgb)") and wet.contains("cs_out("),
		"night street: the reflection is additive, collapsed while dry, its vertex colour decoded on both renderers")
	var road := FileAccess.get_file_as_string("res://shaders/road.gdshader")
	var want := {"mirror_windows": 0.25, "mirror_window_lit": 0.8, "mirror_window_smear": 0.7, "mirror_sky": 1.0}
	for k: String in want:
		var m := RegEx.create_from_string("uniform float " + k + " = ([0-9.]+);").search(road)
		_t._check(m != null and is_equal_approx(m.get_string(1).to_float(), float(want[k])),
			"night street: road.gdshader %s = %s" % [k, m.get_string(1) if m else "missing"])
	_t._check(road.contains("cs_as_uniform(sky_tint.rgb)"), "night street: the wet road's sky is sky_tint in the renderer's own space")


func _lamp_gain(city: Node3D) -> void:
	var day: Node = city.get_node_or_null("DayNight")
	if day == null:
		_t._check(false, "night street: the city has a DayNight")
		return
	var hour: float = day.get("hour")
	var a := OmniLight3D.new()
	var b := OmniLight3D.new()
	b.set_meta("lamp_gain", 0.6)
	for l: OmniLight3D in [a, b]:
		l.add_to_group("lamp_light")
		city.add_child(l)
	day.set("hour", 22.0)
	day.set("_lamp_timer", 0.0)
	day.call("_apply")
	var ea := a.light_energy
	var eb := b.light_energy
	_t._check(ea >= 0.0 and is_equal_approx(eb, ea * 0.6), "night street: a lamp_gain light gets its share of the level (%.2f of %.2f)" % [eb, ea])
	a.queue_free()
	b.queue_free()
	day.set("hour", hour)
	day.set("_lamp_timer", 0.0)
	day.call("_apply")
