extends RefCounted
## The mayhem reference camera (fleet wave 5, rc2-mayhem; docs/HANDOFF.md "The mayhem refcam"):
## checks for tests/smoke_test.gd. CPU and source only (no pixel is read headless):
##   * the camera row exists in tools/refcams/cameras_w5.json with its stage, and the stage script
##     and refcams_shot's hook are there (default off for every other camera);
##   * the fireball volume has the depth-heat / soot look behind `rc_look`, and Blast3 hands it on;
##   * the police pool's soft falloff is gated and every cruiser glow takes it;
##   * the muzzle flash's light reaches a few metres, falling off steeply;
## RC_MAYHEM=0 is the A/B: everything goes back, and the checks only say so.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_camera()
	var em := FileAccess.get_file_as_string("res://scripts/npc/emergency.gd")
	_t._check(em.contains("if not is_instance_valid(item):"), "rc2-mayhem: Emergency's scan skips a wreck freed this frame")
	if not RcMayhem.enabled:
		_t._check(true, "rc2-mayhem: off (RC_MAYHEM=0)")
		return
	_volume()
	_police()
	_muzzle()


func _camera() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in (parsed as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "mayhem":
				row = c
	_t._check(not row.is_empty() and String(row.get("stage", "")) == "mayhem" and float(row.get("hour", 0.0)) == 18.0,
		"rc2-mayhem: the mayhem camera is a staged 18:00 row of cameras_w5.json")
	var shot := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_t._check(shot.contains("if stage == \"mayhem\":") and ResourceLoader.exists("res://tools/refcams/mayhem_stage.gd"),
		"rc2-mayhem: refcams_shot stages only a row that asks for it")
	var plain: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras.json"))
	var staged := 0
	if plain is Dictionary:
		for c: Dictionary in (plain as Dictionary).get("cameras", []):
			if c.has("stage"):
				staged += 1
	_t._check(staged == 0, "rc2-mayhem: none of the ten original cameras is staged")


func _volume() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	_t._check(src.contains("uniform float rc_look = 0.0;") and src.contains("if (rc_look > 0.0)") and src.contains("ds_m *= 0.5;"),
		"rc2-mayhem: the fireball volume's new look is gated (rc_look 0 = the old field)")
	var m := Blast3.volume_material()
	RcMayhem.dress_volume(m)
	_t._check(float(m.get_shader_parameter("rc_look")) == 1.0, "rc2-mayhem: Blast3's volume takes the depth-heat and soot look")
	var b3 := FileAccess.get_file_as_string("res://scripts/weapons/blast_3.gd")
	_t._check(b3.contains("RcMayhem.dress_volume(mat)"), "rc2-mayhem: Blast3.spawn_volume dresses every volume")


func _police() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/police_wash.gdshader")
	_t._check(src.contains("uniform float rc_soft = 0.0;") and src.contains("if (rc_soft > 0.0)"),
		"rc2-mayhem: the police pool's soft falloff is gated (rc_soft 0 = the old pool)")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/police_wash.gdshader")
	RcMayhem.dress_police(m)
	var gain := float(m.get_shader_parameter("rc_pool_gain"))
	_t._check(float(m.get_shader_parameter("rc_soft")) == 1.0 and gain > 0.0 and gain < 0.6,
		"rc2-mayhem: a cruiser's pool is soft and far below the bank's HDR red (gain %.2f)" % gain)
	_t._check(FileAccess.get_file_as_string("res://scripts/npc/police_night_look.gd").contains("RcMayhem.dress_police(mat)"),
		"rc2-mayhem: PoliceNightLook dresses every glow")


func _muzzle() -> void:
	var l := OmniLight3D.new()
	l.omni_range = WeaponFX.muzzle_light_range
	l.omni_attenuation = 1.4
	RcMayhem.dress_muzzle(l)
	_t._check(l.omni_range <= 5.0 and l.omni_attenuation >= 2.0,
		"rc2-mayhem: the muzzle flash lights %.1f m round it, falling off at %.1f (was a 9 m disc)" % [l.omni_range, l.omni_attenuation])
	l.free()
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/gunplay_feel.gd").contains("RcMayhem.dress_muzzle(main)"),
		"rc2-mayhem: GunplayFeel's flash light is dressed")
