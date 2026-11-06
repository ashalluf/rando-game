extends RefCounted
## Fireworks over the ballpark from Stadium Way (the fireworks_ballpark reference camera in
## tools/refcams/cameras_w8.json, docs/HANDOFF.md "Fireworks over the ballpark from Stadium Way"),
## for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads.
##
## Checks: the second look (look5) is in both shaders, off by default (the A/B) and switched on by
## Fireworks' site materials; the smoke over the ballpark takes the floodlit ground; the flash light
## reaches the stands (attenuation); the camera row stands on Stadium Way above the lots with its
## fireworks_t, and that clock holds a big break in the air; refcams_shot.gd handles the key.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	_shaders()
	_camera()
	await _site(city)


func _shaders() -> void:
	var stars := FileAccess.get_file_as_string("res://shaders/fireworks.gdshader")
	var smoke := FileAccess.get_file_as_string("res://shaders/fireworks_smoke.gdshader")
	_t._check(stars.contains("uniform float look5 = 0.0;") and smoke.contains("uniform float look5 = 0.0;"),
		"rc5 fireworks: the second look is off by default in both shaders (the A/B)")
	_t._check(stars.count("look5 > 0.5") >= 3 and smoke.count("look5 > 0.5") >= 2,
		"rc5 fireworks: every new block is behind look5")
	_t._check(stars.contains("v_glow = 0.0;") and stars.contains("float fall = max(1.0 - d2g, 0.0);"),
		"rc5 fireworks: the break's glow is written on every vertex and reaches zero at its quad's edge")
	_t._check(Fireworks.LOOK5_ATTENUATION < 1.0, "rc5 fireworks: the flash light falls off slower than the old 1.2")
	var stadium_omni := pow(300.0, -Fireworks.LOOK5_ATTENUATION) / pow(300.0, -1.2)
	_t._check(stadium_omni > 10.0, "rc5 fireworks: 300 m off, the flash is %.0fx what it was" % stadium_omni)


func _camera() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in table.get("cameras", []):
		if String(c.name) == "fireworks_ballpark":
			row = c
	_t._check(not row.is_empty(), "rc5 fireworks: cameras_w8.json has the fireworks_ballpark row")
	if row.is_empty():
		return
	_t._check(row.has("fireworks_t") and absf(float(row.hour) - 21.5) < 0.01 and String(row.weather) == "clear",
		"rc5 fireworks: the row holds the show clock at 21:30 clear")
	# On Stadium Way: within a road's half width of its polyline, and east of the bowl.
	var eye := Vector2(float(row.eye[0]), float(row.eye[2]))
	var best := INF
	for i in Ballpark.STADIUM_WAY.size() - 1:
		var a: Vector2 = Ballpark.STADIUM_WAY[i]
		var b: Vector2 = Ballpark.STADIUM_WAY[i + 1]
		best = minf(best, eye.distance_to(Geometry2D.get_closest_point_to_segment(eye, a, b)))
	_t._check(best < Ballpark.ROAD_WIDTH * 0.5, "rc5 fireworks: the eye stands on Stadium Way (%.1f m off its line)" % best)
	var src := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_t._check(src.contains("_fireworks_clock(cam)") and src.contains("cam.has(\"fireworks_t\")"),
		"rc5 fireworks: refcams_shot.gd stages the row's show clock")
	# The clock is a big break in the air: the night's show (night 0 at 21:30) has a peony, ring or
	# crossette under a second old, and shells climbing.
	var seed := Fireworks.night_seed(1337, Fireworks.night_of(0, 21.5), "stadium")
	var t_at := float(row.fireworks_t)
	var big := 0
	var rising := 0
	for b in range(int(t_at / Fireworks.BIN) - Fireworks.SLOTS, int(t_at / Fireworks.BIN) + 1):
		var sh := Fireworks.shell(seed, b, Ballpark.RIGHT, 110.0, 95.0, 190.0)
		if sh.is_empty():
			continue
		var a := t_at - float(sh.burst_t)
		if a >= 0.3 and a < 1.2 and int(sh.type) != Fireworks.Type.WILLOW and int(sh.type) != Fireworks.Type.STROBE:
			big += 1
		if t_at >= float(sh.launch) and t_at < float(sh.burst_t):
			rising += 1
	_t._check(big >= 1 and rising >= 1, "rc5 fireworks: the row's clock has a fresh break (%d) and shells rising (%d)" % [big, rising])


func _site(city: Node3D) -> void:
	var fw = city.get_node_or_null("Fireworks") if city else null
	if fw == null or not Fireworks.enabled() or not Ballpark.enabled():
		return
	fw.staged["stadium"] = 31.2
	fw.hold = true
	for i in 2:
		await _t.get_tree().process_frame
	var s: Dictionary = fw.site("stadium")
	_t._check(not s.is_empty(), "rc5 fireworks: the node built its ballpark site")
	if not s.is_empty():
		var on := Fireworks.look5()
		_t._check(float((s.stars as ShaderMaterial).get_shader_parameter("look5")) == (1.0 if on else 0.0)
			and float((s.smoke as ShaderMaterial).get_shader_parameter("look5")) == (1.0 if on else 0.0),
			"rc5 fireworks: the site's materials carry the switch")
		if on:
			var ul: Vector3 = (s.smoke as ShaderMaterial).get_shader_parameter("under_light")
			_t._check(ul.length() > 0.01, "rc5 fireworks: the ballpark's smoke takes the floodlit ground")
			if s.light != null:
				_t._check(is_equal_approx((s.light as OmniLight3D).omni_attenuation, Fireworks.LOOK5_ATTENUATION),
					"rc5 fireworks: the ballpark's flash light uses the slower falloff")
	fw.staged.erase("stadium")
	fw.hold = false
	if not s.is_empty():
		s.active = false
