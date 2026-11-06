extends RefCounted
## The port's truck gate at 10:00 (RcPortGate, tools/refcams/cameras_w8.json's port_gate), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The camera row: 10:00 clear, at eye height inside the gate's chunk, looking toward the canopy.
## The kit: the booth, canopy and portal are new meshes while on (the old ones under RC5_PORT_GATE=0,
## bit for bit the old keys), the barrier fits a lane, the booth glass is port_steel part 15 and the
## shader has it. The queue: the third slot is a bobtail whose rear stays inside the gate's chunk
## and never meets the slot ahead; the odds rise; the gate's chunk is asphalt, every other port
## chunk keeps its concrete.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_kit()
	_queue()
	if plan == null or plan.macro == null:
		return
	_camera(plan)
	_yard(plan)


func _camera(plan: CityPlan) -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	_t._check(f != null, "cameras_w8.json is there")
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "port_gate":
				row = c
	_t._check(not row.is_empty(), "cameras_w8.json has the port_gate row")
	if row.is_empty():
		return
	_t._check(absf(float(row.hour) - 10.0) < 0.01 and String(row.weather) == "clear", "port_gate is 10:00, clear")
	var eye: Array = row.eye
	var g := PortLife.grid(plan)
	var gr := plan.owned_rect(g.gate.x, g.gate.y)
	_t._check(bool(row.get("agl", false)) and float(eye[1]) < 2.0 and gr.has_point(Vector2(float(eye[0]), float(eye[2]))),
		"port_gate stands at eye height inside the gate's chunk (%s in %s)" % [str(eye), str(gr)])
	# It looks toward the canopy (within its field of view).
	var cz := gr.position.y + PortGate.CANOPY_Z
	var to := Vector2(gr.get_center().x, cz) - Vector2(float(eye[0]), float(eye[2]))
	var yaw := deg_to_rad(float(eye[3]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	_t._check(rad_to_deg(fwd.angle_to(to.normalized())) < 40.0 and rad_to_deg(fwd.angle_to(to.normalized())) > -40.0,
		"port_gate looks at the gate's canopy")


func _kit() -> void:
	var was := RcPortGate.enabled
	RcPortGate.enabled = true
	var booth := PortLifeKit.booth_mesh()
	var canopy := PortLifeKit.canopy_mesh(PortGate.LANES)
	var portal := PortLifeKit.portal_mesh(PortGate.LANES)
	var bar := RcPortGate.barrier_mesh()
	RcPortGate.enabled = false
	var old_booth := PortLifeKit.booth_mesh()
	var old_canopy := PortLifeKit.canopy_mesh(PortGate.LANES)
	var old_portal := PortLifeKit.portal_mesh(PortGate.LANES)
	RcPortGate.enabled = was
	_t._check(booth != old_booth and canopy != old_canopy and portal != old_portal, "RcPortGate: the booth, canopy and portal are new meshes while on, the old ones off")
	_t._check(_tris(booth) > _tris(old_booth) and _tris(booth) < 2500 and _tris(canopy) < 4000 and _tris(portal) < 4000,
		"RcPortGate: the gate's meshes are detailed and bounded (booth %d, canopy %d, portal %d triangles)" % [_tris(booth), _tris(canopy), _tris(portal)])
	var bb := bar.get_aabb()
	_t._check(bb.end.x > PortLifeKit.GATE_LANE_W and bb.end.x < PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W
		and bb.end.y < 1.6, "RcPortGate: the barrier's arm spans a lane, stopping short of the next island (%s)" % str(bb))
	var src := FileAccess.get_file_as_string("res://shaders/port_steel.gdshader")
	_t._check(src.contains("part == 15") and int(RcPortGate.S_BOOTH_GLASS) == 15, "port_steel draws the booth glass (part 15)")


func _queue() -> void:
	var was := RcPortGate.enabled
	RcPortGate.enabled = true
	_t._check(RcPortGate.slots() == 3 and RcPortGate.odds(0) > 70 and RcPortGate.odds(1) > 55, "RcPortGate: three slots a lane, busier odds")
	# Rig extents in the lane (facing +Z): front 4.1 m ahead, rear 14.5 m behind (40 ft chassis),
	# a bobtail 3.2 m behind.
	var slot1_rear := 2.0 - 21.5 - 14.5
	var q_front := RcPortGate.QUEUE_Z + 4.1
	var q_rear := RcPortGate.QUEUE_Z - 3.2
	_t._check(q_front < slot1_rear - 0.5, "RcPortGate: the queued bobtail stops behind the rig under the portal (%.1f < %.1f)" % [q_front, slot1_rear])
	_t._check(PortGate.CANOPY_Z + q_rear > 0.0, "RcPortGate: the queued bobtail's rear stays inside the gate's chunk (%.1f m in)" % (PortGate.CANOPY_Z + q_rear))
	var ok := true
	for h: int in [0, 137, 4242, 98765, 1234567, 2147483000]:
		var b := RcPortGate.bobtail(h)
		ok = ok and (b / 100) % 5 == 0 and b % 100 == h % 100 and b >= 0
	_t._check(ok, "RcPortGate.bobtail() keeps the odds roll and makes a bobtail")
	RcPortGate.enabled = false
	_t._check(RcPortGate.slots() == 2 and RcPortGate.odds(0) == 70 and RcPortGate.odds(1) == 55, "RC5_PORT_GATE=0: the old two slots and odds")
	RcPortGate.enabled = was


func _yard(plan: CityPlan) -> void:
	var was := RcPortGate.enabled
	RcPortGate.enabled = true
	var g := PortLife.grid(plan)
	var concrete := StandardMaterial3D.new()
	var gate: Material = RcPortGate.yard(plan, g.gate.x, g.gate.y, concrete)
	var other: Material = RcPortGate.yard(plan, g.gate.x + 1, g.gate.y + 1, concrete)
	_t._check(gate != concrete and other == concrete, "RcPortGate: the gate's chunk is asphalt, the yard keeps its concrete")
	RcPortGate.enabled = false
	_t._check(RcPortGate.yard(plan, g.gate.x, g.gate.y, concrete) == concrete, "RC5_PORT_GATE=0: the gate keeps the yard's concrete")
	RcPortGate.enabled = was


func _tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += m.surface_get_array_index_len(s) / 3
	return n
