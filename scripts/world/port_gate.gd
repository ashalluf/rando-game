class_name PortGate
extends RefCounted
## The container terminal's truck gate (PortLife.is_gate(): the north-west port chunk, where the
## 110 comes in). Trucks come off the street from the north into SIX inbound lanes, pass under
## the OCR / radiation portal (cameras read the box and chassis numbers), stop at the booths under
## the canopy, then roll on into the yard; two outbound lanes on the west side lead back out.
## Drayage semis (BigVehicles SEMI, parked Vehicles of the chunk with the dry van swapped for a
## 40 ft chassis and a box) stand in the lanes: at a booth, queued under the portal, leaving.
## Everything is a hash of seed + lane, never a chunk rng. FULL: the meshes (PortLifeKit), lane
## paint, lettering, collision and the trucks; LOD and the far city: the canopy, booths and office
## as boxes. The terminal's name is invented.

const LANES := 8
const OUT_LANES := 2
const NAME := "BASIN HARBOR TERMINAL"
## Where things stand, metres south of the chunk's north edge.
const PORTAL_Z := 30.0
const CANOPY_Z := 50.0


static func lane_x(area: Rect2, i: int) -> float:
	var w := PortLifeKit.gate_width(LANES)
	return area.get_center().x - w * 0.5 + PortLifeKit.GATE_ISLAND_W + PortLifeKit.GATE_LANE_W * 0.5 + i * (PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W)


static func build(ch: CityChunk, area: Rect2) -> void:
	var cx := area.get_center().x
	var y := CityChunk.PORT_YARD_TOP
	var cz := area.position.y + CANOPY_Z
	var pz := area.position.y + PORTAL_Z
	var w := PortLifeKit.gate_width(LANES)
	var ox := cx + w * 0.5 + 18.0
	var oz := cz - 4.0
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		# Far: the canopy, the booths' row and the office as boxes.
		var boxes := [[Vector3(cx, y + PortLifeKit.CANOPY_Y + 0.7, cz), Vector3(w + 1.0, 1.4, 14.0), Color(0.82, 0.83, 0.82)],
			[Vector3(cx, y + 1.5, cz), Vector3(w - 4.0, 3.0, 3.0), Color(0.7, 0.7, 0.68)],
			[Vector3(ox, y + 3.8, oz), Vector3(22.0, 7.6, 12.0), Color(0.76, 0.75, 0.71)]]
		for bx: Array in boxes:
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis.from_scale(bx[1]), bx[0]), bx[2],
					Color(0.25, 0.05, 0.37, 0.0))
		return
	ch._batch.add("port_gate_canopy", PortLifeKit.canopy_mesh(LANES), Transform3D(Basis(), Vector3(cx, y, cz)))
	ch._batch.add("port_gate_portal", PortLifeKit.portal_mesh(LANES), Transform3D(Basis(), Vector3(cx, y, pz)))
	ch._batch.add("port_gate_office", PortLifeKit.office_mesh(), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(ox, y, oz)))
	ch._add_shape(Vector3(12.0, 7.6, 22.0), Vector3(ox, y + 3.8, oz))
	var hw := w * 0.5
	for i in LANES + 1:
		var ix := cx - hw + PortLifeKit.GATE_ISLAND_W * 0.5 + i * (PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W)
		ch._batch.add("port_gate_booth", PortLifeKit.booth_mesh(), Transform3D(Basis(), Vector3(ix, y, cz)))
		ch._add_shape(Vector3(PortLifeKit.GATE_ISLAND_W, 0.4, 18.0), Vector3(ix, y + 0.2, cz))
		ch._add_shape(Vector3(1.8, 3.0, 3.4), Vector3(ix, y + 1.5, cz))
		for z: float in [cz - 5.8, cz + 5.8]:
			ch._add_shape(Vector3(0.5, PortLifeKit.CANOPY_Y, 0.5), Vector3(ix, y + PortLifeKit.CANOPY_Y * 0.5, z))
		ch._add_shape(Vector3(0.4, 6.0, 0.4), Vector3(ix, y + 3.0, pz))
		# Lane lines run from the street to the canopy between the islands.
		ch._port_line(Vector2(ix, area.position.y + 1.0), Vector2(ix, cz - 9.2), 0.15, CityChunk.PORT_PAINT_WHITE)
	ch._add_shape(Vector3(w + 1.0, 1.4, 14.0), Vector3(cx, y + PortLifeKit.CANOPY_Y + 0.7, cz))
	for i in LANES:
		var lx := lane_x(area, i)
		var outbound := i < OUT_LANES
		# Stop bar at the booth, a yellow hatch in the outbound lanes' mouth.
		var stop_z := cz + (-6.0 if outbound else 6.0)
		ch._port_line(Vector2(lx - 2.1, stop_z), Vector2(lx + 2.1, stop_z), 0.4, CityChunk.PORT_PAINT_WHITE)
		_lettering(ch, "%d" % (i + 1), 0.9, Color(0.95, 0.95, 0.9), Vector3(lx, y + 6.0 + 1.8, pz - 0.17), PI)
		_lettering(ch, "OUT" if outbound else "IN", 0.5, Color(0.95, 0.8, 0.2), Vector3(lx, y + 6.0 + 1.4, pz - 0.17), PI)
	_lettering(ch, NAME, 0.75, Color(0.95, 0.95, 0.92), Vector3(cx, y + PortLifeKit.CANOPY_Y + 0.75, cz - 7.08), PI)
	_lettering(ch, "GATE OFFICE", 0.6, Color(0.95, 0.95, 0.92), Vector3(ox - 6.1, y + 6.4, oz), -PI * 0.5)
	# The trucks, a build step each (a semi is ~35 ms to build).
	for i in LANES:
		for slot in 2:
			var h := absi(hash([ch.plan.seed, "gate_truck", i, slot]))
			var outbound := i < OUT_LANES
			if outbound and slot == 1:
				continue
			var odds := 70 if slot == 0 else 55
			if h % 100 >= odds:
				continue
			var z := cz + 2.0 - slot * 21.5
			var yaw := PI
			if outbound:
				z = cz - 14.0
				yaw = 0.0
			var at := Vector3(lane_x(area, i), y + ch._pgy(0.0, 0.0), z)
			ch._run_or_defer(_spawn_truck.bind(ch, at, yaw, h))


static func _lettering(ch: CityChunk, text: String, size: float, color: Color, at: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BigVehicles.text_mesh(text, size, color)
	mi.name = "GateText"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.rotation.y = yaw
	mi.visibility_range_end = 160.0
	ch.add_child(mi)


## One drayage semi in a gate lane: a parked Vehicle of the chunk (it sleeps; it can be stolen),
## its dry van hidden and a chassis with a box (or nothing: a bobtail) hitched instead.
static func _spawn_truck(ch: CityChunk, at: Vector3, yaw: float, h: int) -> bool:
	if not PhysicsBudget.can_spawn() or not is_instance_valid(ch):
		return true
	var car := BigVehicles.make(BigVehicles.SEMI, h)
	var holder: Node = ch.get_parent() if ch.get_parent() else ch
	var pos := at + Vector3(0.0, 0.3, 0.0)
	car.position = WorldState.to_local(pos) if holder != ch else pos
	car.rotation.y = yaw
	car.set_meta("port_dray", true)
	holder.add_child(car)
	car.visible = ch.visible
	ch._cars.append(car)
	var trailer := car.get_node_or_null("Trailer") as Node3D
	if trailer:
		trailer.visible = false
		for c in trailer.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true
	if (h / 100) % 5 == 0:
		# A bobtail: no trailer, so no trailer box either.
		var hitch := car.get_node_or_null("Hitch")
		if hitch and hitch.get("_shape"):
			(hitch.get("_shape") as CollisionShape3D).disabled = true
		return true
	var d := car._dims()
	var kp: Vector3 = d.get("kingpin", Vector3(0.0, 0.92, 2.874))
	var road := float(d.get("road", -0.3))
	var chassis := MeshInstance3D.new()
	chassis.name = "PortChassis"
	chassis.mesh = PortLifeKit.chassis_mesh()
	chassis.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, road, kp.z + PortLifeKit.CHASSIS_KINGPIN))
	car.add_child(chassis)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var look := PortKit.container_look(rng.randi() % PortKit.LIVERY_COUNT, rng)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = PropFactory.container()
	mm.instance_count = 1
	mm.set_instance_transform(0, PortKit.container_xform(Vector3(0.0, PortLifeKit.CHASSIS_BED + PortKit.H_STD * 0.5, 0.0), true, rng.randf() < 0.3, rng.randf() < 0.5))
	mm.set_instance_color(0, look[0])
	mm.set_instance_custom_data(0, look[1])
	var box := MultiMeshInstance3D.new()
	box.name = "PortBox"
	box.multimesh = mm
	chassis.add_child(box)
	return true
