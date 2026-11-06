extends RefCounted
## STARLIGHT PLAZA on an event night (ArenaNight, the arena_night reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the spill shader picks the screen's slide the way led_screen.gdshader does; the plaza
## builds its spill pools, the facades' LED and the name near and far; the hotel's crown lantern and
## bigger name; event nights from a hash (and ARENA_EVENT forcing them); the searchlights; the event
## crowd; the camera row stands on the plaza; ARENA_NIGHT=0 builds the district as before.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var was := ArenaNight.enabled
	ArenaNight.enabled = true
	_shader()
	_events()
	_plaza(true)
	_hotel()
	_beams()
	_camera(city)
	ArenaNight.enabled = false
	_plaza(false)
	_t._check(ArenaNight.crowd_gain(46) == 46 and is_equal_approx(ArenaNight.hotel_name_height(3.2), 3.2),
		"ARENA_NIGHT=0: the plaza's crowd and the hotel's name as before")
	ArenaNight.enabled = was
	ArenaNight.event_now = false


func _shader() -> void:
	var spill := FileAccess.get_file_as_string("res://shaders/arena_spill.gdshader")
	var led := FileAccess.get_file_as_string("res://shaders/led_screen.gdshader")
	for pair: Array in [["float clock = TIME + seed * 17.0;", "float clock = TIME + seed * 17.0;"],
			["float slot = floor(clock / slide_seconds);", "float slot = floor(clock / slide_seconds);"],
			["hue(lm_hash21(vec2(k, seed + 1.0)))", "hue(lm_hash21(vec2(float(k), seed + 1.0)))"],
			["hue(lm_hash21(vec2(k + 7.0, seed + 2.0)))", "hue(lm_hash21(vec2(float(k) + 7.0, seed + 2.0)))"],
			["smoothstep(0.0, 0.5, since)", "smoothstep(0.0, 0.5, since)"]]:
		_t._check(spill.contains(pair[0]) and led.contains(pair[1]), "the spill picks the screen's slide as the screen does: %s" % pair[1])
	_t._check(spill.contains("mod(slot + seed * 5.0, float(slide_count))") and led.contains("mod(slot + seed * 5.0, float(slide_count))"),
		"the spill and the screen count slides the same way")
	_t._check(spill.contains("af_cover(") and spill.contains("blend_add"), "the spill is additive with a coverage alpha (the fog rule)")
	var led_src := FileAccess.get_file_as_string("res://shaders/arena_led.gdshader")
	_t._check(led_src.contains("mix(day_level, 1.0, clamp(lamp_factor") and led_src.contains("uniform float day_level = 0.18;"),
		"the facade LED is full after dark and a dull line by day (never a glow at noon)")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/arena_spill.gdshader")
	_t._check(mat.shader.get_shader_uniform_list().size() >= 5, "the spill shader parses")


func _events() -> void:
	var prev := OS.get_environment("ARENA_EVENT")
	OS.set_environment("ARENA_EVENT", "")
	var on := 0
	for n in 400:
		if ArenaNight.event_tonight(1337, n):
			on += 1
	_t._check(on > 200 and on < 300, "events on about %.0f %% of nights (%d of 400)" % [ArenaNight.EVENT_ODDS * 100.0, on])
	OS.set_environment("ARENA_EVENT", "1")
	_t._check(ArenaNight.event_tonight(1337, 3) and ArenaNight.event_tonight(7, 11), "ARENA_EVENT=1 forces an event")
	OS.set_environment("ARENA_EVENT", "0")
	_t._check(not ArenaNight.event_tonight(1337, 3), "ARENA_EVENT=0 forces a quiet night")
	OS.set_environment("ARENA_EVENT", prev)
	ArenaNight.event_now = true
	_t._check(ArenaNight.crowd_gain(46) == roundi(46.0 * ArenaNight.EVENT_CROWD), "an event night fills the plaza")
	ArenaNight.event_now = false
	_t._check(ArenaNight.crowd_gain(46) == 46, "a quiet night keeps the plaza's count")


func _count(n: Node, prefix: String) -> int:
	var c := 1 if String(n.name).begins_with(prefix) else 0
	for k in n.get_children():
		c += _count(k, prefix)
	return c


func _has_surface(n: Node, mat: Material) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		for i in m.get_surface_count():
			if m.surface_get_material(i) == mat:
				return true
	for k in n.get_children():
		if _has_surface(k, mat):
			return true
	return false


func _plaza(on: bool) -> void:
	var s := Rect2(Vector2(-72.5, -86.8), Vector2(145.0, 173.6))
	for detailed: bool in [true, false]:
		var holder := Node3D.new()
		var body := StaticBody3D.new()
		holder.add_child(body)
		LandmarkArenaDistrict.build("live_plaza", s, 0.25, holder, body, detailed)
		var spills := _count(holder, "ArenaSpill")
		var led := _has_surface(holder, ArenaNight.led_material("led", ArenaNight.LED_GAIN))
		if on:
			_t._check(spills == (4 if detailed else 0), "%s plaza: %d spill pools (three wall screens and the theatre's column near, none far)" % ["near" if detailed else "far", spills])
			_t._check(led, "%s plaza: the facades' LED blades and coves" % ("near" if detailed else "far"))
		else:
			_t._check(spills == 0 and not led, "ARENA_NIGHT=0: no spill, no facade LED (%s)" % ("near" if detailed else "far"))
		holder.free()


func _hotel() -> void:
	var s := Rect2(Vector2(-45.0, -35.0), Vector2(90.0, 70.0))
	var holder := Node3D.new()
	var body := StaticBody3D.new()
	holder.add_child(body)
	LandmarkArenaDistrict.build("live_hotel", s, 0.25, holder, body, false)
	_t._check(_has_surface(holder, ArenaNight.led_material("crown", ArenaNight.CROWN_GAIN)), "the hotel's crown is lit from inside (far copy too)")
	_t._check(ArenaNight.hotel_name_height(3.2) > 3.2, "the hotel's name is bigger on its long faces")
	holder.free()


func _beams() -> void:
	var holder := Node3D.new()
	var batch := MultiMeshBatch.new()
	ArenaNight.searchlights(holder, batch, [Vector3(0.0, 0.0, 0.0), Vector3(10.0, 5.0, 0.5)], 0.25, 4471)
	var beams := 0
	for k in holder.get_children():
		if k is SkyBeam:
			beams += 1
	_t._check(beams == 2 and batch.keys().has("an_cart"), "an event night's searchlights: a cart and a beam each")
	holder.free()


func _camera(city: Node) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in (data as Dictionary).get("cameras", []):
		if c.get("name", "") == "arena_night":
			row = c
	_t._check(not row.is_empty() and int(row.get("arena_event", 0)) == 1, "the arena_night camera row asks for an event night")
	var plan: Variant = city.get("plan")
	if row.is_empty() or plan == null:
		return
	var info := CivicSites.site(plan, "live_plaza")
	var p := CivicSites.rect_to_world(info, LandmarkArenaDistrict._plaza_open(info.local))
	var eye := Vector2(float(row.eye[0]), float(row.eye[2]))
	_t._check(p.has_point(eye), "the arena_night eye stands on STARLIGHT PLAZA (%s in %s)" % [str(eye), str(p)])
