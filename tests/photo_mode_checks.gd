extends RefCounted
## Photo mode (scripts/ui/photo_mode.gd), for tests/smoke_test.gd. Loaded at run time, not named
## there, so it compiles after the autoloads.
##
## Opens photo mode in the city and checks: the world is frozen (paused tree, time scale 0, held
## through the weapon wheel's per-frame time reset), the HUD is hidden, its own camera is in
## force and stays inside its radius and above the street; every setting lands where it should
## (field of view, depth of field, exposure, the clock, the weather, a grade in the look LUT,
## vignette and grain, letterbox bars, the player hidden); a photo is written as a PNG; it will
## not open over the pause menu; and leaving puts back every one of those things exactly.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var photo: Node = city.get_node_or_null("PhotoMode")
	_t._check(photo != null and photo.get_parent() == city, "photo mode is built beside the pause menu in the city scene")
	if photo == null:
		return
	var has_p := false
	for e in InputMap.action_get_events("photo_mode") if InputMap.has_action("photo_mode") else []:
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_P:
			has_p = true
	_t._check(has_p, "the photo_mode action is bound to P")

	var tree := city.get_tree()
	var day: Node = city.get_node_or_null("DayNight")
	var weather: Node = city.get_node_or_null("Weather")
	var env: Environment = (city.get_node("WorldEnvironment") as WorldEnvironment).environment
	var player := tree.get_first_node_in_group("player") as Node3D
	var hud := city.get_node_or_null("DebugHud") as CanvasLayer
	var cam_before := city.get_viewport().get_camera_3d()
	var hour_before: float = float(day.get("hour"))
	var weather_before := {}
	var weather_mode := weather.process_mode
	for key in (photo.get_script() as Script).get_script_constant_map()["WEATHER_KEYS"]:
		weather_before[key] = weather.get(key)
	var sat_before := env.adjustment_saturation
	var lut_before := env.adjustment_color_correction
	var vig: ShaderMaterial = photo.call("_vignette_material")
	var vig_before: Variant = vig.get_shader_parameter("strength") if vig else null
	var grain_before: Variant = vig.get_shader_parameter("grain") if vig else null
	var hud_before := hud.visible if hud else false
	var scale_before := Engine.time_scale

	# Not over the pause menu.
	var menu: Node = city.get_node("PauseMenu")
	menu.call("open")
	_t._check(not bool(photo.call("can_open")), "photo mode does not open over the pause menu")
	menu.call("close")

	photo.call("open")
	await tree.process_frame
	await tree.process_frame
	var cam: Camera3D = photo.get("camera")
	_t._check(bool(photo.call("is_open")) and tree.paused and Engine.time_scale == 0.0,
		"photo mode freezes the world (paused, time scale %.2f)" % Engine.time_scale)
	_t._check(cam != null and cam.current and city.get_viewport().get_camera_3d() == cam and cam != cam_before,
		"photo mode flies its own camera")
	_t._check(hud == null or not hud.visible, "photo mode hides the HUD")
	if cam:
		var anchor: Vector3 = photo.get("_anchor")
		var far: Vector3 = photo.call("_clamp_position", anchor + Vector3(5000.0, 0.0, 0.0))
		var low: Vector3 = photo.call("_clamp_position", anchor + Vector3(3.0, -500.0, 0.0))
		var g: float = float(city.call("ground_height_at", low))
		_t._check(far.distance_to(anchor) <= float(photo.get("max_radius")) + 0.01 and low.y >= g + 0.2,
			"the free camera stays within %.0f m of the player and above the street" % float(photo.get("max_radius")))

	# Settings.
	photo.call("set_fov", 32.0)
	photo.call("set_dof", true)
	photo.call("set_focus", 20.0)
	photo.call("set_fstop", 2.0)
	photo.call("set_exposure", 1.0)
	var attrs := cam.attributes as CameraAttributesPractical if cam else null
	# Depth of field only where the renderer has it (not Compatibility, not the headless check):
	# elsewhere photo mode leaves the fields alone (setting them only warns).
	var dof_ok := false
	if attrs:
		if bool(photo.call("dof_supported")):
			dof_ok = attrs.dof_blur_far_enabled and attrs.dof_blur_near_enabled and attrs.dof_blur_far_distance > 20.0 \
				and attrs.dof_blur_near_distance < 20.0
		else:
			dof_ok = not attrs.dof_blur_far_enabled and not attrs.dof_blur_near_enabled
	_t._check(cam != null and absf(cam.fov - 32.0) < 0.01 and dof_ok
		and absf(attrs.exposure_multiplier - 2.0) < 0.001 and attrs != cam_before.attributes,
		"field of view, depth of field (where the renderer has it) and exposure are set on photo mode's own camera")
	photo.call("set_hour", 21.5)
	photo.call("set_weather", 3)
	photo.call("set_grade", 5)
	_t._check(absf(float(day.get("hour")) - 21.5) < 0.01 and int(weather.get("state")) == 3
		and env.adjustment_saturation == 0.0 and env.adjustment_color_correction != lut_before,
		"photo mode sets the clock, the weather and a black-and-white grade")
	# A grade with no gain, lift or contrast is the scene's own look LUT.
	var base := (lut_before as GradientTexture1D).gradient if lut_before is GradientTexture1D else null
	var same: GradientTexture1D = photo.call("grade_texture", base, Color(1, 1, 1), Color(0, 0, 0), 0.0)
	var worst := 0.0
	for i in 11:
		var x := i / 10.0
		var a: Color = same.gradient.sample(x)
		var b: Color = base.sample(x) if base else Color(x, x, x)
		worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
	_t._check(worst < 0.01, "a neutral grade leaves the look LUT as it is (worst %.4f)" % worst)
	photo.call("set_vignette", 0.8)
	photo.call("set_grain", 0.08)
	photo.call("set_frame", 1)
	photo.call("set_hide_player", true)
	await tree.process_frame
	var bar: ColorRect = photo.get("_bar_a")
	_t._check(bar.visible and bar.size.y > 1.0 and (vig == null or absf(float(vig.get_shader_parameter("strength")) - 0.8) < 0.001)
		and (player == null or not player.visible),
		"letterbox bars, vignette and hiding the player apply")
	_t._check(Engine.time_scale == 1.0 and float(photo.get("_settle")) > 0.0 and weather.process_mode == Node.PROCESS_MODE_ALWAYS,
		"a change into a storm lets the weather run a moment before the world freezes again")

	# Saving.
	photo.set("save_dir_override", "user://photo_mode_test")
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.5, 0.8))
	var path: String = photo.call("save_image", img)
	var back := Image.load_from_file(path) if path != "" else null
	_t._check(path.ends_with(".png") and back != null and back.get_width() == 64 and back.get_height() == 36,
		"TAKE PHOTO writes a PNG (%s)" % path)
	if path != "":
		DirAccess.remove_absolute(path)
	# The real capture: the panel hides, the frame is read back; under the dummy renderer there
	# may be no frame to read, which must not leave photo mode stuck mid-capture.
	photo.call("take_photo")
	for i in 8:
		await tree.process_frame
	var panel_ok := (photo.get("_ui") as Control).visible or bool(photo.get("_capturing"))
	_t._check(panel_ok, "a capture puts the panel back (or is still waiting for the frame)")

	photo.call("close")
	# Read at once: the next frame the weather and the clock run on again.
	var weather_back := true
	for key in weather_before:
		if weather.get(key) != weather_before[key]:
			weather_back = false
			printerr("photo mode: weather %s %s != %s" % [key, str(weather.get(key)), str(weather_before[key])])
	var hour_back := absf(float(day.get("hour")) - hour_before) < 0.001
	var mode_back := weather.process_mode == weather_mode
	await tree.process_frame
	_t._check(not tree.paused and Engine.time_scale == scale_before and city.get_viewport().get_camera_3d() == cam_before
		and (not is_instance_valid(cam) or cam.is_queued_for_deletion()),
		"leaving photo mode restores the pause, the time scale and the camera")
	_t._check(hour_back and weather_back and mode_back,
		"leaving photo mode restores the clock and the weather")
	_t._check(env.adjustment_saturation == sat_before and env.adjustment_color_correction == lut_before
		and (vig == null or (vig.get_shader_parameter("strength") == vig_before and vig.get_shader_parameter("grain") == grain_before))
		and (player == null or player.visible) and (hud == null or hud.visible == hud_before)
		and not (photo.get("_bar_a") as ColorRect).is_visible_in_tree(),
		"leaving photo mode restores the grade, vignette, grain, player and HUD")
	DirAccess.remove_absolute("user://photo_mode_test")
