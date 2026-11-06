extends RefCounted
## The window washers from the roof next door (Rc5TowerGondola, the tower_gondola reference camera
## in tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks: the camera row stands on the neighbour's roof across the street from dt_park_c's east
## face and its gondola_t holds the cradle washing a pane in the frame; the ropes and lanyards are
## the min-pixel rope shader on a forced rig; the water shader's look is off by default and switched
## on by the rig; RC5_GONDOLA=0 puts the old materials back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was: bool = Rc5TowerGondola.enabled
	Rc5TowerGondola.enabled = true
	_camera()
	_shaders()
	_rig(city, true)
	Rc5TowerGondola.enabled = false
	_t._check(TowerGondolas.rope_material(Color(0.3, 0.3, 0.3)) is StandardMaterial3D,
		"RC5_GONDOLA=0: the old rope material")
	_rig(city, false)
	Rc5TowerGondola.enabled = was


func _camera() -> void:
	var f := FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json")
	var row: Dictionary = {}
	for cam: Dictionary in (JSON.parse_string(f) as Dictionary).get("cameras", []):
		if cam.name == "tower_gondola":
			row = cam
	_t._check(not row.is_empty() and row.has("gondola_t") and float(row.hour) == 10.0 and row.weather == "clear",
		"the tower_gondola camera row is there at 10:00 clear with its gondola_t")
	if row.is_empty():
		return
	_t._check(FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd").contains("_gondola_clock(cam)"),
		"refcams_shot holds the cradles' clock for a row's gondola_t")
	var site: Dictionary = TowerGondolas.landmark_sites("dt_park_c", 1337).hung[0]
	var a: Vector2 = LandmarkDowntown.anchor("dt_park_c")
	var p := TowerGondolas.pose_at(site, float(row.gondola_t))
	var c: Vector3 = Vector3(a.x, 0.0, a.y) + (site.m as Vector3) + (site.t as Vector3) * float(p.lane)
	var eye := Vector3(row.eye[0], row.eye[1], row.eye[2])
	var d := Vector2(c.x - eye.x, c.z - eye.z)
	# In the frame: within the lens' half width of where it looks (forward is -Z).
	var yaw := deg_to_rad(float(row.eye[3]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var off := rad_to_deg(acos(clampf(fwd.dot(d.normalized()), -1.0, 1.0)))
	_t._check(int(p.moving) == 0 and float(p.step) > 0.2 and float(p.step) < 0.8,
		"at gondola_t the cradle is half way through washing a pane (step %.2f)" % float(p.step))
	_t._check(d.length() > 20.0 and d.length() < 45.0 and off < 38.0,
		"the cradle is %.0f m from the eye, %.0f degrees off the look (in the frame)" % [d.length(), off])


func _shaders() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/gondola_streaks.gdshader")
	_t._check(src.contains("uniform float look = 0.0;"), "the water's new look is off by default (the A/B)")
	var rope := load("res://shaders/gondola_rope.gdshader") as Shader
	_t._check(rope != null and FileAccess.get_file_as_string("res://shaders/gondola_rope.gdshader").contains("min_px"),
		"the rope shader loads and widens to a minimum pixel width")
	var m: Material = TowerGondolas.rope_material(TowerGondolas.ROPE_ORANGE)
	_t._check(m is ShaderMaterial and (m as ShaderMaterial).shader == rope, "a lanyard wears the rope shader")


## A forced rig on dt_park_c: its ropes, lanyards and water take the pass (on) or not (off).
func _rig(city: Node3D, on: bool) -> void:
	var holder := Node3D.new()
	holder.name = "Rc5GondolaCheck"
	city.add_child(holder)
	TowerGondolas.landmark(holder, Vector3(0.0, -4000.0, 0.0), "dt_park_c")
	var rigs: Array = holder.find_children("GondolaRig", "Node3D", true, false)
	if rigs.is_empty():
		_t._check(false, "dt_park_c carries a gondola rig")
		holder.free()
		return
	var rig = rigs[0]
	rig.force = true
	rig._manage()
	rig._update(1.0 / 60.0)
	var ropes_ok: bool = not rig._ropes.is_empty()
	for r: MeshInstance3D in rig._ropes:
		ropes_ok = ropes_ok and ((r.material_override is ShaderMaterial) == on)
	for l: MeshInstance3D in rig._lanyards:
		ropes_ok = ropes_ok and ((l.material_override is ShaderMaterial) == on)
	var look := float((rig._streak_mat as ShaderMaterial).get_shader_parameter("look"))
	_t._check(ropes_ok and is_equal_approx(look, 1.0 if on else 0.0),
		"%s: the rig's ropes, lanyards and water %s" % ["RC5_GONDOLA on" if on else "RC5_GONDOLA=0", "take the pass" if on else "are the old ones"])
	rig.force = false
	rig._drop()
	holder.free()
