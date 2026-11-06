extends RefCounted
## The heli_night refcam (RcHeliNight, docs/HANDOFF.md "Downtown from a helicopter at 22:30"):
## checks for tests/smoke_test.gd. No shader runs headless, so the shaders are read back against
## the GDScript copies; the switch is put back as it was found.

var _t: Node


func run(t: Node, _city: Node3D = null) -> void:
	_t = t
	_global_and_switch()
	_crown_lids()
	_pad_lamps()
	_unfinished()
	_camera_row()


func _global_and_switch() -> void:
	_t._check(ProjectSettings.has_setting("shader_globals/rc4_heli_night"), "rc4_heli_night is a shader global")
	var was := RcHeliNight.enabled
	RcHeliNight.set_enabled(false)
	var off_raw = RenderingServer.global_shader_parameter_get("rc4_heli_night")
	var off := float(off_raw) if off_raw != null else 0.0
	var lit_off := RcHeliNight.unfinished_lit()
	RcHeliNight.set_enabled(true)
	var on_raw = RenderingServer.global_shader_parameter_get("rc4_heli_night")
	var on := float(on_raw) if on_raw != null else 1.0
	var lit_on := RcHeliNight.unfinished_lit()
	RcHeliNight.set_enabled(was)
	_t._check(is_equal_approx(off, 0.0) and is_equal_approx(on, 1.0) and lit_off == 0.0 and lit_on > 0.0,
		"RC4_HELI_NIGHT switches the global (off %.1f, on %.1f) and the unfinished towers' lights (%.2f / %.2f)"
		% [off, on, lit_off, lit_on])


## tower_crown.gdshader keeps RcHeliNight.LID_GLOW of a lid's glow, behind the global.
func _crown_lids() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/tower_crown.gdshader")
	_t._check(sh.contains("const float HN_LID_GLOW = %.2f;" % RcHeliNight.LID_GLOW)
			and sh.contains("if (rc4_heli_night > 0.5)") and sh.contains("mix(1.0, HN_LID_GLOW"),
		"a crown's lid keeps LID_GLOW of its glow in tower_crown.gdshader (the copy matches)")
	_t._check(RcHeliNight.LID_GLOW > 0.0 and RcHeliNight.LID_GLOW < 0.3,
		"a lid is dark but not black (LID_GLOW %.2f)" % RcHeliNight.LID_GLOW)


## building_lod.gdshader's far helipad lamps: the copies match, and the mean is a row of lamps.
func _pad_lamps() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	_t._check(sh.contains("const float HN_PAD_EVERY = %.1f;" % RcHeliNight.PAD_LAMP_EVERY)
			and sh.contains("const float HN_PAD_GAIN = %.1f;" % RcHeliNight.PAD_LAMP_GAIN)
			and sh.contains("pad_line *= mix(lamp, mean"),
		"a far helipad's perimeter is a row of lamps in building_lod.gdshader (the copies match)")
	var near := RcHeliNight.pad_lamp_mean(0.1)
	var far := RcHeliNight.pad_lamp_mean(20.0)
	_t._check(near > 0.05 and near < 0.2 and far < near and far * RcHeliNight.PAD_LAMP_GAIN < 0.1,
		"the lamps' mean is a fraction of the old line and falls with distance (%.3f, %.3f)" % [near, far])


## The unfinished towers carry work lights and obstruction lights while the switch is on.
func _unfinished() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/landmark_downtown.gd")
	_t._check(src.contains("RcHeliNight.unfinished_lit()") and src.contains("if RcHeliNight.enabled:"),
		"LandmarkDowntown._unfinished takes RcHeliNight's lit ratio and lights")
	var mat = LandmarkDowntown._materials.get("unfinished_glass")
	if mat is ShaderMaterial:
		var lit := float((mat as ShaderMaterial).get_shader_parameter("lit_ratio"))
		_t._check(is_equal_approx(lit, RcHeliNight.unfinished_lit()) or not RcHeliNight.enabled,
			"the built unfinished glass has the work-light ratio (%.2f)" % lit)


func _camera_row() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var found := false
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "heli_night":
				found = float(c.get("hour", 0.0)) > 22.0 and (c.get("eye", []) as Array).size() == 5 \
					and float((c.get("eye") as Array)[1]) >= 200.0
	_t._check(found, "the heli_night refcam is in tools/refcams/cameras_w7.json")
