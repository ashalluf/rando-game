extends RefCounted
## The coyote_night refcam's fixes (wave 8, rc5-coyote-night; Rc5CoyoteNight), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The small hours: a suburban house block keeps SMALL_HOURS_KEEP of its walkers at 02:00, all of
## them by day and in the evening, downtown untouched. The timers: on in the evening, off from
## 00:30, the shaders' copy of the numbers and the flag. The shaft: no cone in clear air. Eyeshine:
## a staged coyote carries two sprites on its head bone. The camera row.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null:
		_t._check(false, "rc5_coyote_night: the city has a plan")
		return
	var was := Rc5CoyoteNight.enabled
	Rc5CoyoteNight.enabled = true
	_hours(plan)
	_shaders()
	_eyes(city)
	_row()
	Rc5CoyoteNight.enabled = false
	_t._check(is_equal_approx(Rc5CoyoteNight.crowd_gain(plan, _suburb_rect(plan), 2.0), 1.0) and is_equal_approx(Rc5CoyoteNight.timer_alpha(0.5), 0.5),
		"Rc5CoyoteNight: RC5_COYOTE_NIGHT=0 keeps the whole crowd and flags no timer")
	Rc5CoyoteNight.enabled = was


func _suburb_rect(plan: CityPlan) -> Rect2:
	var bi := plan.block_index_at(Vector2(1255.0, 4200.0))
	var b: Dictionary = plan.block(bi.x, bi.y)
	return b.get("rect", Rect2(1204, 4147, 98, 83))


func _hours(plan: CityPlan) -> void:
	var r := _suburb_rect(plan)
	_t._check(Rc5CoyoteNight.house_block(plan, r), "Rc5CoyoteNight: the coyote_night refcam's block is a suburban house block")
	_t._check(is_equal_approx(Rc5CoyoteNight.crowd_gain(plan, r, 2.0), Rc5CoyoteNight.SMALL_HOURS_KEEP),
		"Rc5CoyoteNight: a house block at 02:00 keeps %.2f of its walkers" % Rc5CoyoteNight.SMALL_HOURS_KEEP)
	_t._check(is_equal_approx(Rc5CoyoteNight.crowd_gain(plan, r, 13.0), 1.0) and is_equal_approx(Rc5CoyoteNight.crowd_gain(plan, r, 21.5), 1.0),
		"Rc5CoyoteNight: by day and at 21:30 the house block keeps its whole crowd")
	var down := Rect2(2750.0, 60.0, 100.0, 80.0)
	_t._check(not Rc5CoyoteNight.house_block(plan, down) and is_equal_approx(Rc5CoyoteNight.crowd_gain(plan, down, 2.0), 1.0),
		"Rc5CoyoteNight: downtown keeps BusyStreets' own night crowd")
	var mono := true
	var prev := 2.0
	for i in 13:
		var s := Rc5CoyoteNight.small_hours(22.0 + float(i) * 0.25)
		mono = mono and s <= prev + 1e-6
		prev = s
	_t._check(mono, "Rc5CoyoteNight: the small hours empty the street gradually from 22:00 to 01:00")
	_t._check(is_equal_approx(Rc5CoyoteNight.timer_level(21.0), 1.0) and is_equal_approx(Rc5CoyoteNight.timer_level(2.0), 0.0)
		and is_equal_approx(Rc5CoyoteNight.timer_level(5.5), 0.0) and is_equal_approx(Rc5CoyoteNight.timer_level(19.0), 1.0),
		"Rc5CoyoteNight: landscape timers on in the evening, off from 00:30 until morning")
	_t._check(is_equal_approx(Rc5CoyoteNight.timer_alpha(0.5), 0.5 + Rc5CoyoteNight.TIMER_FLAG), "Rc5CoyoteNight: a timed glow carries the flag")


func _shaders() -> void:
	for path: String in ["res://shaders/house_glow.gdshader", "res://shaders/house_lamp.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		var copy := src.contains("(h - %.1f) / (%.1f - %.1f)" % [Rc5CoyoteNight.TIMER_OFF_FROM, Rc5CoyoteNight.TIMER_OFF_BY, Rc5CoyoteNight.TIMER_OFF_FROM])
		_t._check(copy and src.contains("uniform float timer_look = 0.0"), "Rc5CoyoteNight: %s holds the timers' numbers behind timer_look" % path.get_file())
	var glow := FileAccess.get_file_as_string("res://shaders/house_glow.gdshader")
	_t._check(glow.contains("strength > 1.5") and glow.contains("strength - 2.0"), "Rc5CoyoteNight: house_glow reads the timer flag (alpha + 2)")
	var shaft := FileAccess.get_file_as_string("res://shaders/night_shaft.gdshader")
	_t._check(shaft.contains("uniform float clear_cut = 0.0") and shaft.contains("smoothstep(0.32, 0.6, haze)") and NightAtmos.HAZE_BY_STATE[0] <= 0.32,
		"Rc5CoyoteNight: the lamp shaft is gone in clear air (CLEAR haze %.2f)" % NightAtmos.HAZE_BY_STATE[0])
	var eye := FileAccess.get_file_as_string("res://shaders/wild_eyeshine.gdshader")
	_t._check(eye.contains("fog_disabled") and eye.contains("lamp_factor") and eye.contains("min_px"),
		"Rc5CoyoteNight: the eyeshine is additive with the fog off, lit after dark, never under min_px")
	var on := 1.0 if Rc5CoyoteNight.enabled else 0.0
	_t._check(is_equal_approx(float(HouseNights.glow_mesh(1).material.get_shader_parameter("timer_look")), on)
		and is_equal_approx(float(NightAtmos.atmos_material("shaft").get_shader_parameter("clear_cut")), on),
		"Rc5CoyoteNight: the glow and shaft materials carry the switch")


func _eyes(city: Node3D) -> void:
	var wl: Wildlife = city.get_node_or_null("Wildlife")
	if wl == null:
		_t._check(false, "Rc5CoyoteNight: the city has its Wildlife node")
		return
	var an := wl.stage("coyote", Vector2(1257.5, 4239.0), 0.0, 11, true)
	var att := an.rig.skeleton.get_node_or_null("Eyeshine") as BoneAttachment3D
	var n := att.get_child_count() if att else 0
	var ok := att != null and att.bone_name == "Head" and n == 2
	if ok:
		var a := (att.get_child(0) as Node3D).position
		var b := (att.get_child(1) as Node3D).position
		ok = a.distance_to(b) > 0.03 and a.distance_to(b) < 0.2
	_t._check(ok, "Rc5CoyoteNight: a coyote carries a pair of eyeshine sprites on its head bone, either side of its face (%d)" % n)
	an.queue_free()


func _row() -> void:
	var f := FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json")
	var data: Variant = JSON.parse_string(f)
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "coyote_night":
				row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 2.0) and row.has("wildlife"),
		"Rc5CoyoteNight: cameras_w8.json has the coyote_night row at 02:00 with its staged wildlife")
