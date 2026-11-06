extends RefCounted
## The speedboat_golden refcam's fixes (BoatSea, scripts/vehicles/boat_sea.gd; BoatWake; the
## refcam staging), for tests/smoke_test.gd: a boat under way at sea hands the ocean shader a wake
## in its packing (bow, heading, speed, beam, trail, hull + strength), a still one, one in the
## marina or one sinking hands none; OceanTraffic's push merges it with the vessels and turns the
## warm foam on (wake_glow); the shader has the uniform and its default is the old foam; the
## transom carries lettering at NEAR and MID only; the boat's wake throws its spray sheets and
## leaves the flat foam quads off at sea; BOAT_SEA=0 hands no wake, sets no glow and letters no
## transom; the refcam row and its staging script are there.
## Untyped access to the city (autoloads, see smoke_test.gd).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_check_static()
	await _check_live(city)


func _check_static() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	_check(src.contains("uniform float wake_glow = 0.0;"), "ocean.gdshader has wake_glow, off by default (the old foam)")
	var cams = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if cams is Dictionary:
		for c in cams.get("cameras", []):
			if String(c.get("name", "")) == "speedboat_golden":
				row = c
	_check(not row.is_empty() and row.has("boat") and float(row.get("hour", 0.0)) > 17.0,
		"cameras_w8.json has speedboat_golden with its boat staging key at golden hour")
	_check(ResourceLoader.exists("res://tools/refcams/boat_stage.gd"), "the refcam's boat staging script exists")
	# The transom: lettering at NEAR and MID, nothing at FAR.
	var h := BoatKit._hull_of(BoatKit.Kind.SPEEDBOAT)
	var counts := []
	for lv in 3:
		var acc := BoatMesh.Acc.new()
		acc.level = lv
		BoatSea.transom(acc, h, 1, BoatKit.ACCENTS[1])
		counts.append(acc.triangles())
	_check(counts[0] > 40 and counts[1] > 40 and counts[2] == 0, "the transom carries a name at NEAR and MID only (%s)" % str(counts))
	var front := true
	var acc2 := BoatMesh.Acc.new()
	BoatSea.transom(acc2, h, 2, BoatKit.ACCENTS[2])
	var tz := BoatMesh._z(h, 0.0)
	for i in acc2.n.size():
		if acc2.n[i].z < 0.99 or acc2.v[i].z < tz:
			front = false
			break
	_check(front, "the transom lettering faces aft, on the transom's face")
	BoatSea.enabled = false
	var acc3 := BoatMesh.Acc.new()
	BoatSea.transom(acc3, h, 1, BoatKit.ACCENTS[1])
	BoatSea.enabled = true
	_check(acc3.triangles() == 0, "BOAT_SEA=0: no transom lettering")


func _check_live(city: Node3D) -> void:
	var plan = city.get("plan")
	var m: MacroMap = plan.macro if plan else null
	if m == null:
		_check(false, "the boat checks have the city's map")
		return
	var at := Vector2(m.coast_x(3500.0) - 320.0, 3500.0)
	var b := Boat.new()
	b.name = "Rc5SeaBoat"
	b.setup_boat(BoatKit.Kind.SPEEDBOAT, 11)
	b.position = WorldState.to_local(Vector3(at.x, 0.3, at.y))
	b.rotation.y = deg_to_rad(96.0)
	city.add_child(b)
	b.set_physics_process(false)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	await _t.get_tree().physics_frame
	_check(BoatSea.boats.has(b), "a boat registers with BoatSea")
	var fx = b.get("_fx")
	_check(fx != null and (fx.get("_sheets") as Array).size() == 2, "the boat's wake has its two spray sheets")
	b.wet = 1.0
	b.set("_kind", SwimWater.Kind.SEA)
	var head := Vector2(-sin(deg_to_rad(96.0)), -cos(deg_to_rad(96.0)))
	b.linear_velocity = Vector3(head.x, 0.0, head.y) * 16.0
	var e := BoatSea.entry(b)
	var ok := e.size() == 2
	if ok:
		var a: Vector4 = e[0]
		var w: Vector4 = e[1]
		var bw := WorldState.to_world(b.global_position)
		var bow := Vector2(bw.x, bw.z) + head * BoatKit.SIZE[0].x * 0.5
		ok = Vector2(a.x, a.y).distance_to(bow) < 0.05 and Vector2(a.z, a.w).distance_to(head) < 0.01
		ok = ok and absf(w.x - 16.0) < 0.1 and absf(w.y - BoatKit.SIZE[0].y) < 0.01
		ok = ok and w.z > 300.0 and w.z <= BoatSea.TRAIL_MAX and floorf(w.w) == 7.0 and absf(fmod(w.w, 1.0) / 0.99 - 1.0) < 0.01
	_check(ok, "a speedboat at 16 m/s hands the shader its wake: bow, heading, speed, beam, trail, hull + strength (%s)" % str(e))
	var cam := WorldState.to_world(b.global_position) + Vector3(0.0, 4.0, 15.0)
	_check(BoatSea.entries(cam, 100.0).size() >= 1 and BoatSea.entries(cam + Vector3(5000.0, 0.0, 0.0), 100.0).filter(func(x: Array) -> bool: return absf(x[0] - 5000.0) < 30.0).is_empty(),
		"entries() takes a boat within reach, not one past it")
	# OceanTraffic's push merges it (when the traffic runs) and turns the warm foam on.
	var ot: Node = null
	for n in _t.get_tree().get_nodes_in_group("ocean_traffic"):
		if bool(n.get("enabled")):
			ot = n
	var mat := PropFactory.ocean_material()
	if ot != null and mat != null:
		ot.call("push_wakes")
		var wa: PackedVector4Array = mat.get_shader_parameter("wake_a")
		var found := false
		for v in wa:
			if Vector2(v.x, v.y).distance_to(Vector2((e[0] as Vector4).x, (e[0] as Vector4).y)) < 0.5:
				found = true
		var reach := float(ot.get("wake_range"))
		var near_cam := WorldState.to_world(_t.get_tree().root.get_viewport().get_camera_3d().global_position) if _t.get_tree().root.get_viewport().get_camera_3d() else Vector3.ZERO
		var in_reach := near_cam.distance_to(WorldState.to_world(b.global_position)) < reach
		_check(found or not in_reach, "OceanTraffic's push hands the ocean the boat's wake beside the vessels'")
		_check(absf(float(mat.get_shader_parameter("wake_glow")) - BoatSea.GLOW) < 0.001, "the push turns the wakes' warm foam on (wake_glow)")
	else:
		BoatSea.push_alone(_t.get_tree())
		_check(mat == null or float(mat.get_shader_parameter("wake_glow")) > 0.5, "with OceanTraffic off the boats push their own wakes and glow")
	# Still, in the marina, sinking: no wake.
	b.linear_velocity = Vector3.ZERO
	_check(BoatSea.entry(b).is_empty(), "a still boat hands no wake")
	b.linear_velocity = Vector3(head.x, 0.0, head.y) * 16.0
	b.set("_kind", SwimWater.Kind.MARINA)
	_check(BoatSea.entry(b).is_empty() and not b.on_sea(), "a boat in the marina hands the sea no wake")
	b.set("_kind", SwimWater.Kind.SEA)
	b.sinking = true
	_check(BoatSea.entry(b).is_empty(), "a sinking boat hands no wake")
	b.sinking = false
	# BOAT_SEA=0: nothing.
	BoatSea.enabled = false
	var off := BoatSea.entries(cam, 1000.0).is_empty()
	if mat:
		BoatSea.apply(mat)
		off = off and float(mat.get_shader_parameter("wake_glow")) == 0.0
	BoatSea.enabled = true
	if mat:
		BoatSea.apply(mat)
	_check(off, "BOAT_SEA=0: no boat wakes and no glow")
	b.queue_free()
	await _t.get_tree().physics_frame
	await _t.get_tree().physics_frame
	_check(not BoatSea.boats.has(b), "a freed boat leaves BoatSea")
	if ot != null:
		ot.call("push_wakes")


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
