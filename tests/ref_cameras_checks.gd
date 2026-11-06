extends RefCounted
## The reference cameras (tools/refcams/) for tests/smoke_test.gd: the table parses, holds ten
## uniquely named cameras with an hour, a weather the Weather node knows and a five-number eye,
## an absolute eye stands over the ground there, and the shot script still compiles against the
## still_shot.gd it extends.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras.json"))
	_t._check(parsed is Dictionary, "refcams: cameras.json parses")
	if not parsed is Dictionary:
		return
	var cams: Array = (parsed as Dictionary).get("cameras", [])
	_t._check(cams.size() == 10, "refcams: ten reference cameras (%d)" % cams.size())
	var keys: Array = (load("res://scripts/world/weather.gd") as GDScript).get_script_constant_map().get("STATE_KEYS", [])
	var plan: Variant = city.get("plan")
	var names := {}
	var bad := []
	for c: Dictionary in cams:
		var n := String(c.get("name", ""))
		var eye: Array = c.get("eye", [])
		var hour := float(c.get("hour", -1.0))
		var ok := n != "" and not names.has(n) and eye.size() == 5 and hour >= 0.0 and hour < 24.0 \
			and String(c.get("weather", "")) in keys
		if ok and not c.get("agl", false) and plan != null:
			ok = float(eye[1]) > float(plan.height_at(Vector2(float(eye[0]), float(eye[2])))) + 0.3
		names[n] = true
		if not ok:
			bad.append(n)
	_t._check(bad.is_empty(), "refcams: every camera has a name, eye, hour and weather, over the ground %s" % [bad])
	var script := load("res://tools/refcams/refcams_shot.gd") as GDScript
	_t._check(script != null and script.can_instantiate(), "refcams: the shot script compiles")
