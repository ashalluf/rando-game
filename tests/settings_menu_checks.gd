extends RefCounted
## Settings checks for tests/smoke_test.gd (GameSettings, the pause menu's SETTINGS screen): the
## defaults are the game as it was; values are clamped and snapped; a file round-trips and a bad
## one falls back; applied, every value lands on its knob (the camera rig, the buses, CameraPost,
## Quality's render scale, the vignette layer, the HUD's scale); the screen's sliders and chips
## change the values and leaving it writes the file. Everything runs on a TEST path, and the
## scene, the buses and the file are put back exactly as they were, so no later check sees it.

const TEST_PATH := "user://settings_menu_test.cfg"

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var saved_path := GameSettings.path
	var saved_values := GameSettings.values.duplicate()
	var saved_hud := GameSettings.hud_scale
	GameSettings.path = TEST_PATH
	_check_pure()
	_check_file()
	if GameSettings.enabled():
		await _check_scene(city)
	else:
		_check(city.get_node("PauseMenu").get("_settings_view") == null,
			"settings are off (SETTINGS_MENU=0): no settings screen is built")
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_check(not FileAccess.file_exists(TEST_PATH), "the settings checks leave no file behind")
	GameSettings.path = saved_path
	GameSettings.values = saved_values
	GameSettings.hud_scale = saved_hud


func _check_pure() -> void:
	var d := GameSettings.DEFAULTS
	var rig_script: Script = load("res://scripts/player/camera_rig.gd")
	var rig_fov := 75.0
	for p in rig_script.get_script_property_list():
		if p.name == "camera_fov":
			rig_fov = float(rig_script.get_property_default_value("camera_fov"))
	_check(is_equal_approx(float(d.fov), rig_fov) and is_equal_approx(float(d.car_fov), rig_fov)
			and float(d.mouse_sensitivity) == 1.0 and float(d.render_scale) == 1.0
			and float(d.hud_scale) == 1.0 and bool(d.motion_blur) and bool(d.depth_of_field)
			and bool(d.film_grain) and bool(d.vignette) and not bool(d.invert_y)
			and float(d.volume_master) == 1.0,
		"the settings' defaults are the game as it was (fov %.0f, every multiplier 1, every effect on)" % rig_fov)
	var ranged := true
	for key: String in d:
		if d[key] is bool:
			continue
		var r: Array = GameSettings.RANGES.get(key, [])
		ranged = ranged and r.size() == 3 and float(d[key]) >= r[0] and float(d[key]) <= r[1]
	_check(ranged, "every number setting has a range that holds its default")
	var clamp_ok := float(GameSettings.sanitize("fov", 500.0)) == 100.0 \
			and float(GameSettings.sanitize("volume_world", -3.0)) == 0.0 \
			and is_equal_approx(float(GameSettings.sanitize("mouse_sensitivity", 1.234)), 1.25) \
			and float(GameSettings.sanitize("render_scale", NAN)) == 1.0 \
			and float(GameSettings.sanitize("hud_scale", "big")) == 1.0 \
			and GameSettings.sanitize("invert_y", 1) is bool
	_check(clamp_ok, "settings are clamped to their range, snapped to their step and typed")


func _check_file() -> void:
	GameSettings.reset()
	GameSettings.set_value("fov", 88.0)
	GameSettings.set_value("invert_y", true)
	GameSettings.set_value("volume_ambience", 0.4)
	var err := GameSettings.save_file()
	GameSettings.reset()
	GameSettings.load_file()
	_check(err == OK and float(GameSettings.get_value("fov")) == 88.0 and bool(GameSettings.get_value("invert_y"))
			and is_equal_approx(float(GameSettings.get_value("volume_ambience")), 0.4)
			and float(GameSettings.get_value("car_fov")) == 75.0,
		"settings round-trip through the ConfigFile (and an unset key keeps its default)")
	var cfg := ConfigFile.new()
	cfg.set_value(GameSettings.SECTION, "fov", "wide")
	cfg.set_value(GameSettings.SECTION, "hud_scale", 9.0)
	cfg.set_value(GameSettings.SECTION, "no_such_key", 3)
	cfg.save(TEST_PATH)
	GameSettings.load_file()
	_check(float(GameSettings.get_value("fov")) == 75.0 and float(GameSettings.get_value("hud_scale")) == 1.5
			and not GameSettings.values.has("no_such_key"),
		"a bad settings file falls back to defaults and clamps what it can")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameSettings.load_file()
	_check(GameSettings.values == GameSettings.DEFAULTS, "no settings file means every default")


func _check_scene(city: Node3D) -> void:
	var player := _tree.get_first_node_in_group("player")
	var rig: Node = player.get_node_or_null("CameraRig") if player else null
	var post: Node = _tree.get_first_node_in_group("camera_post")
	var quality: Node = city.get_node_or_null("Quality")
	var menu: Node = city.get_node("PauseMenu")
	_check(rig != null and post != null and quality != null, "the settings' targets exist (camera rig, CameraPost, Quality)")
	if rig == null or post == null or quality == null:
		return
	# What is there now, to put back.
	var keep_rig := {}
	for k in ["mouse_sensitivity", "gamepad_look_speed", "invert_y", "camera_fov", "car_fov"]:
		keep_rig[k] = rig.get(k)
	var keep_meta := {}
	for m in ["gs_mouse", "gs_pad"]:
		keep_meta[m] = rig.get_meta(m) if rig.has_meta(m) else null
	var keep_post := [post.get("motion_blur_enabled"), post.get("user_dof")]
	var keep_scale := float(quality.get("user_scale"))
	var keep_bus := {}
	for key: String in GameSettings.BUSES:
		var idx := AudioServer.get_bus_index(GameSettings.BUSES[key])
		if idx >= 0:
			keep_bus[idx] = [AudioServer.get_bus_volume_db(idx), AudioServer.is_bus_mute(idx)]
	var vig := city.get_node_or_null("Vignette")
	var vig_mat: ShaderMaterial = null
	if vig and vig.get_child_count() > 0:
		vig_mat = (vig.get_child(0) as CanvasItem).material as ShaderMaterial
	var keep_vig := [vig_mat.get_shader_parameter("strength"), vig_mat.get_shader_parameter("grain")] if vig_mat else []
	var frame := _tree.root.find_child("MinimapFrame", true, false) as Control
	var frame_scale := frame.scale.x if frame else 0.0

	GameSettings.reset()
	GameSettings.apply(city)
	var base_mouse := float(rig.get("mouse_sensitivity"))
	var base_pad := float(rig.get("gamepad_look_speed"))
	var values := {"mouse_sensitivity": 2.0, "invert_y": true, "fov": 90.0, "car_fov": 100.0,
		"volume_master": 0.5, "volume_world": 0.0, "volume_ambience": 0.25, "motion_blur": false,
		"depth_of_field": false, "film_grain": false, "vignette": false, "render_scale": 0.75,
		"hud_scale": 1.25}
	for key: String in values:
		GameSettings.set_value(key, values[key])
	GameSettings.apply(city)
	_check(is_equal_approx(float(rig.get("mouse_sensitivity")), base_mouse * 2.0)
			and is_equal_approx(float(rig.get("gamepad_look_speed")), base_pad * 2.0)
			and bool(rig.get("invert_y")) and float(rig.get("camera_fov")) == 90.0
			and float(rig.get("car_fov")) == 100.0,
		"look sensitivity, invert and both fields of view land on the camera rig")
	var master := AudioServer.get_bus_index(&"Master")
	var world := AudioServer.get_bus_index(&"World")
	var amb := AudioServer.get_bus_index(&"Ambience")
	_check(master >= 0 and absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.5)) < 0.01
			and (world < 0 or AudioServer.is_bus_mute(world))
			and (amb < 0 or absf(AudioServer.get_bus_volume_db(amb) - linear_to_db(0.25)) < 0.01),
		"the volumes set the Master, World and Ambience buses (zero mutes)")
	_check(not bool(post.get("motion_blur_enabled")) and not bool(post.get("user_dof"))
			and is_equal_approx(float(quality.get("user_scale")), 0.75),
		"motion blur, depth of field and the render scale reach CameraPost and Quality")
	_check(vig_mat == null or (float(vig_mat.get_shader_parameter("strength")) == 0.0
			and float(vig_mat.get_shader_parameter("grain")) == 0.0),
		"vignette and film grain off clear the lens layer")
	_check(frame == null or (absf(frame.scale.x / frame_scale - 1.25) < 0.01),
		"the HUD size scales the minimap (%.3f -> %.3f)" % [frame_scale, frame.scale.x if frame else 0.0])
	# Depth of field off: no far blur even in the ambient state.
	for i in 3:
		await _tree.process_frame
	var cam := rig.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	var attrs := cam.attributes as CameraAttributesPractical if cam else null
	_check(attrs == null or not attrs.dof_blur_far_enabled, "depth of field off leaves no far blur")

	# The screen: open it, drag a slider, press a chip, leave it (which saves).
	GameSettings.reset()
	GameSettings.apply(city)
	menu.call("open")
	menu.call("_show_settings", true)
	var controls: Dictionary = menu.get("settings_controls")
	_check(bool(menu.call("settings_open")) and controls.size() == GameSettings.DEFAULTS.size(),
		"the settings screen opens with a control for every setting (%d)" % controls.size())
	var fov_slider := controls.get("fov") as HSlider
	var blur_on := controls.get("motion_blur") as Button
	if fov_slider and blur_on:
		fov_slider.value = 82.0
		(blur_on.get_meta("off") as Button).emit_signal("pressed")
		_check(float(GameSettings.get_value("fov")) == 82.0 and float(rig.get("camera_fov")) == 82.0
				and not bool(GameSettings.get_value("motion_blur")) and not bool(post.get("motion_blur_enabled")),
			"the screen's slider and chips change the settings and apply them at once")
	menu.call("_show_settings", false)
	var cfg := ConfigFile.new()
	_check(cfg.load(TEST_PATH) == OK and float(cfg.get_value(GameSettings.SECTION, "fov", 0.0)) == 82.0
			and not bool(cfg.get_value(GameSettings.SECTION, "motion_blur", true)),
		"leaving the settings screen saves them")
	menu.call("_show_settings", true)
	menu.call("_reset_settings")
	_check(GameSettings.values == GameSettings.DEFAULTS and is_equal_approx(fov_slider.value, 75.0),
		"reset to defaults puts every value and control back")
	menu.call("_show_settings", false)
	menu.call("close")

	# Put everything back as it was.
	GameSettings.reset()
	GameSettings.apply(city)
	for k: String in keep_rig:
		rig.set(k, keep_rig[k])
	for m: String in keep_meta:
		if keep_meta[m] == null:
			rig.remove_meta(m)
		else:
			rig.set_meta(m, keep_meta[m])
	post.set("motion_blur_enabled", keep_post[0])
	post.set("user_dof", keep_post[1])
	quality.set("user_scale", keep_scale)
	for idx: int in keep_bus:
		AudioServer.set_bus_volume_db(idx, keep_bus[idx][0])
		AudioServer.set_bus_mute(idx, keep_bus[idx][1])
	if vig_mat:
		vig_mat.set_shader_parameter("strength", keep_vig[0])
		vig_mat.set_shader_parameter("grain", keep_vig[1])
	_check(not _tree.paused and (frame == null or is_equal_approx(frame.scale.x, frame_scale)),
		"the settings checks leave the game unpaused and the HUD at its size")


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
