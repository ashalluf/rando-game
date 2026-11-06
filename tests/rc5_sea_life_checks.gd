extends RefCounted
## The sea_life refcam (rc5-sea-life) for tests/smoke_test.gd, loaded at run time. Checks: the
## camera row is in cameras_w8.json (08:00 clear, its "sea" staging key); the spray's second look
## is on (SeaLife.spray_look, the spray material's look2, the dolphin's skin2) and the shader
## carries its branches; a surfacing dolphin and a pelican sitting down leave rings on the water
## (SPRAY_RING) that lie at the sea and age out; the staged pod surfaces one after another, never
## all six in the air at once. SEA_SPRAY=0 is the A/B.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_row()
	_shader()
	var sea: Node = city.get_node_or_null("SeaLife")
	if sea == null:
		_t._check(false, "rc5 sea life: the SeaLife node is in the city")
		return
	var plan: CityPlan = city.get("plan")
	sea.call("setup_plan", plan)
	_rings(sea, plan)
	sea.call("clear_stage")


func _row() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "sea_life":
				row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 8.0) and String(row.get("weather", "")) == "clear"
		and String(row.get("sea", "")).contains("dolphin") and String(row.get("sea", "")).contains("pelican"),
		"rc5 sea life: the sea_life row is in cameras_w8.json, 08:00 clear, staging a pod and a pelican line")


func _shader() -> void:
	_t._check(SeaLife.spray_look == (OS.get_environment("SEA_SPRAY") != "0"), "rc5 sea life: the spray's second look follows SEA_SPRAY")
	var on := 1.0 if SeaLife.spray_look else 0.0
	_t._check(is_equal_approx(float(SeaLife.spray_material().get_shader_parameter("look2")), on)
		and is_equal_approx(float(SeaLife.material("dolphin").get_shader_parameter("skin2")), on),
		"rc5 sea life: the spray material's look2 and the dolphin's skin2 are set by it")
	var src := FileAccess.get_file_as_string("res://shaders/sea_spray.gdshader")
	_t._check(src.contains("uniform float look2") and src.contains("k > 2.5") and src.contains("flat_q") and src.contains("streak"),
		"rc5 sea life: sea_spray.gdshader lays white water flat, streaks the throw and draws the rings")
	var life := FileAccess.get_file_as_string("res://shaders/sea_life.gdshader")
	_t._check(life.contains("uniform float skin2") and life.contains("skin2 > 0.0"), "rc5 sea life: sea_life.gdshader has the dolphin's wet skin pass")


func _rings(sea: Node, plan: CityPlan) -> void:
	var m := plan.macro
	var z := 400.0
	var at := Vector2(m.coast_x(z) - 120.0, z)
	sea.call("stage", "dolphin", at, 0.4)
	var forced: Array = sea.get("_forced")
	if forced.is_empty():
		_t._check(false, "rc5 sea life: a pod stages")
		return
	var e: Dictionary = forced[0]
	var clock := SeaLife.clock
	# The staged moment: the pod comes up one after another, not all in the air together.
	var at_moment: Array = sea.call("dolphins_at", e, clock + 0.4)
	var airborne := 0
	for d in at_moment:
		var p: Vector3 = d.pos
		if p.y - float(sea.call("sea_y", Vector2(p.x, p.z))) > 0.3:
			airborne += 1
	_t._check(airborne >= 1 and airborne < int(e.count), "rc5 sea life: the staged pod surfaces in turn (%d of %d in the air at the moment)" % [airborne, int(e.count)])
	var rings := 0
	var on_sea := true
	var aged := true
	for i in 120:
		var splash: Array = []
		sea.call("dolphins_at", e, clock + float(i) * 0.25, splash)
		for s in splash:
			if float(s.kind) == SeaLife.SPRAY_RING:
				rings += 1
				var p: Vector3 = s.pos
				on_sea = on_sea and absf(p.y - float(sea.call("sea_y", Vector2(p.x, p.z)))) < 1.5
				aged = aged and float(s.age) >= 0.0 and float(s.age) < 4.0
	if SeaLife.spray_look:
		_t._check(rings > 0 and on_sea and aged, "rc5 sea life: surfacing dolphins leave rings on the sea that age out in 4 s (%d)" % rings)
	else:
		_t._check(rings == 0, "rc5 sea life: no rings under SEA_SPRAY=0")
	# A pelican that sits down after its plunge leaves a ring too.
	sea.call("stage", "dive", Vector2(m.coast_x(0.0) - 90.0, 0.0), 4.0)
	forced = sea.get("_forced")
	var pel_rings := 0
	if not forced.is_empty():
		for i in 70:
			var splash: Array = []
			sea.call("pelicans_at", forced[0], SeaLife.clock + float(i) * 0.25, splash)
			for s in splash:
				if float(s.kind) == SeaLife.SPRAY_RING:
					pel_rings += 1
	_t._check(pel_rings > 0 or not SeaLife.spray_look, "rc5 sea life: a pelican sitting down after its plunge leaves a ring (%d)" % pel_rings)
