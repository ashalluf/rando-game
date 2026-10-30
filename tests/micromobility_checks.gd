extends RefCounted
## Micromobility (Micromobility, MicroMesh, BikeRider, Cyclists), for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## Checks the meshes (one surface on the shader, under budget, every part), the plan (pure, busy
## round downtown and thin in the suburbs, the named streets' lanes, the rider's line on the
## kerb side), a FULL chunk with a bike lane (the paint batch, no parked car in the lane, nothing
## else in the block moved with it off), one with scooters (knockable, gone for good once
## knocked), and a rider (the pose: hands on the grips and feet on the pedals; riding its lane on
## its line; stopping at a red; knocked off into a ragdoll and a thrown bike).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_meshes()
	_plan(plan)
	var lane := _find_lane(plan)
	_t._check(lane.x != 99999, "a bike lane runs near downtown")
	if lane.x != 99999:
		_lane_chunk(city, plan, lane)
	var scoot := _find_item(plan, Micromobility.Item.SCOOTER)
	_t._check(scoot.x != 99999, "scooters stand on a block near downtown")
	if scoot.x != 99999:
		_scooter_chunk(city, plan, scoot)
	if lane.x != 99999:
		await _rider(city, plan, lane)


func _meshes() -> void:
	var ok := true
	var worst := 0
	for k in MicroMesh.Kind.size():
		var m := MicroMesh.whole(k)
		var tris := MicroMesh.triangles(m)
		worst = maxi(worst, tris)
		ok = ok and m.get_surface_count() == 1 and m.surface_get_material(0) == MicroMesh.material() and tris > 500
		for p: String in ["frame", "front", "rear"]:
			ok = ok and MicroMesh.triangles(MicroMesh.part(k, p)) > 50
	for m: Mesh in [MicroMesh.dock(), MicroMesh.kiosk(), MicroMesh.rack(), MicroMesh.delineator(), Micromobility.lane_mesh()]:
		ok = ok and m.get_surface_count() == 1 and MicroMesh.triangles(m) >= 2
	_t._check(ok, "every micromobility mesh is one surface on its shader, every rider part built")
	_t._check(worst < 8000, "a bike or scooter stays under 8k triangles (worst %d)" % worst)


func _plan(plan: CityPlan) -> void:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	var counts := [0, 0, 0]
	var again := [0, 0, 0]
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for v: Dictionary in Micromobility.plan_block(plan, centre.x + dx, centre.y + dz):
				counts[int(v.item)] += 1
			for v: Dictionary in Micromobility.plan_block(plan, centre.x + dx, centre.y + dz):
				again[int(v.item)] += 1
	_t._check(counts == again, "the micromobility plan is pure (the same twice)")
	_t._check(counts[0] >= 12 and counts[1] >= 2 and counts[2] >= 8,
		"downtown has scooter clusters, share stations and racks (%d, %d, %d round its centre)" % counts)
	# The rider's line is on the kerb side of its direction (as TrafficManager's lanes).
	var off_x := Micromobility.ride_offset(plan, CityPlan.AXIS_X, 3, 1)
	var off_z := Micromobility.ride_offset(plan, CityPlan.AXIS_Z, 3, 1)
	var w := plan.road_width(CityPlan.AXIS_X, 3)
	_t._check(off_x < 0.0 and off_z > 0.0 and absf(absf(off_x) - (w * 0.5 - Micromobility.RIDE_LINE)) < 0.01,
		"a rider keeps right: %.2f m off an AXIS_X road's centre going +z, %.2f off an AXIS_Z road's going +x" % [off_x, off_z])
	# A named street keeps its lane wherever it is open city (7th St downtown).
	var named := false
	for axis in 2:
		for i in range(-30, 60):
			if plan.road_name(axis, i).to_upper() == "7TH ST":
				named = Micromobility.road_has_lane(plan, axis, i)
	_t._check(named, "7th St has its bike lane")


## A block near downtown whose +x or +z road has a lane: (ix, iz, axis).
func _find_lane(plan: CityPlan) -> Vector3i:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	for r in 6:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				for axis in 2:
					if Micromobility.lane_by_chunk(plan, axis, k.x, k.y):
						var span := Micromobility.lane_span(plan, axis, k.x + 1 if axis == 0 else k.y + 1, k.y if axis == 0 else k.x)
						if span.y - span.x > 60.0:
							return Vector3i(k.x, k.y, axis)
	return Vector3i(99999, 99999, 0)


func _find_item(plan: CityPlan, item: int) -> Vector2i:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	for r in 6:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				for v: Dictionary in Micromobility.plan_block(plan, k.x, k.y):
					if int(v.item) == item:
						return k
	return Vector2i(99999, 99999)


func _lane_chunk(city: Node3D, plan: CityPlan, lane: Vector3i) -> void:
	var k := Vector2i(lane.x, lane.y)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var node := chunk.get_node_or_null("Batch_" + Micromobility.K_LANE) as MultiMeshInstance3D
	_t._check(node != null and int(chunk.get_meta("bike_lane_pieces", 0)) > 4 and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"a lane road's chunk paints its bike lanes (%d pieces, one batch, no shadow)" % int(chunk.get_meta("bike_lane_pieces", 0)))
	var in_lane := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).position) if (car as Node).get_parent() != chunk else (car as Node3D).position
			if Micromobility.blocks_parking(chunk, p):
				in_lane += 1
	_t._check(in_lane == 0, "no parked car stands in a bike lane (%d)" % in_lane)
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	Micromobility.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	Micromobility.enabled = true
	_t._check(_signature(bare) == sig, "micromobility rolls nothing from the block: built without it it is the same block")
	bare.get_parent().remove_child(bare)
	bare.free()


func _scooter_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var item: EncampmentItem = null
	var n := 0
	for c in chunk.get_children():
		if c is EncampmentItem and String(c.name).begins_with("Micro_"):
			n += 1
			if item == null:
				item = c
	_t._check(item != null and n <= Micromobility.MAX_ITEMS, "a chunk's scooters and bikes stand as knockable bodies (%d, at most %d)" % [n, Micromobility.MAX_ITEMS])
	if item == null:
		chunk.get_parent().remove_child(chunk)
		chunk.free()
		return
	var id := item.item_id
	item.knock(Vector3(4.0, 3.0, 0.0))
	_t._check(WorldState.is_destroyed(chunk.key, id), "a knocked scooter is remembered as gone")
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var again: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	again.build()
	var back := false
	for c in again.get_children():
		if c is EncampmentItem and (c as EncampmentItem).item_id == id:
			back = true
	_t._check(not back, "a knocked-over scooter does not stand back up when its chunk is rebuilt")
	again.get_parent().remove_child(again)
	again.free()


func _rider(city: Node3D, plan: CityPlan, lane: Vector3i) -> void:
	var cyc := city.get_node_or_null("Cyclists") as Cyclists
	_t._check(cyc != null, "the city has its Cyclists")
	if cyc == null:
		return
	var axis := lane.z
	var index := lane.x + 1 if axis == 0 else lane.y + 1
	var k := lane.y if axis == 0 else lane.x
	var span := Micromobility.lane_span(plan, axis, index, k)
	# A road bike rider halfway down the lane, going +.
	var s := span.x + 10.0
	var rider := cyc.place_rider(axis, index, 1, s, MicroMesh.Kind.ROAD, 6.0, 7)
	rider.pose_now()
	# The pose: the wrists a palm short of the grips, the ankles over the pedals.
	var sk := rider._sk
	_t._check(sk != null, "a rider's rig is posed by the riding solve")
	if sk != null:
		var to_rider := rider._to_skel.affine_inverse()
		var g: Dictionary = MicroMesh.GEO[MicroMesh.Kind.ROAD]
		var grip: Vector3 = g.grip
		var worst_hand := 0.0
		for side in 2:
			var hb: int = rider._b.LeftHand if side == 0 else rider._b.RightHand
			var wrist := to_rider * sk.get_bone_global_pose(hb).origin
			var gp := Vector3(grip.x * (-1.0 if side == 0 else 1.0), grip.y, grip.z) * rider._bike_scale
			worst_hand = maxf(worst_hand, wrist.distance_to(gp))
		_t._check(worst_hand < 0.16, "a rider's hands are on the bars (worst wrist %.2f m from its grip)" % worst_hand)
		var worst_foot := 0.0
		for side in 2:
			var fb: int = rider._b.LeftFoot if side == 0 else rider._b.RightFoot
			var ankle := to_rider * sk.get_bone_global_pose(fb).origin
			var pedal := rider.pedal_at(1 if side == 0 else 0) * rider._bike_scale
			worst_foot = maxf(worst_foot, Vector2(ankle.y - pedal.y, ankle.z - pedal.z).length())
		_t._check(worst_foot < 0.22, "a rider's feet are on the pedals (worst ankle %.2f m from its pedal)" % worst_foot)
	# Riding: along the lane, on its line.
	var start := rider.position
	for i in 30:
		await _t.get_tree().physics_frame
	var moved := rider.position - start
	var along := moved.z if axis == 0 else moved.x
	var line := plan.road_pos(axis, index) + Micromobility.ride_offset(plan, axis, index, 1)
	var lateral := rider.position.x if axis == 0 else rider.position.z
	_t._check(along > 1.5 and absf(lateral - line) < 0.05, "a rider rides its lane on its line (%.1f m in half a second, %.3f m off the line)" % [along, absf(lateral - line)])
	# A red at the crossing ahead: it stops short of the line.
	var next_k := k + 1
	var ix := index if axis == 0 else next_k
	var iz := next_k if axis == 0 else index
	if TrafficSignals.is_signal(plan, ix, iz):
		var stopper := cyc.place_rider(axis, index, 1, span.y - 14.0, MicroMesh.Kind.CRUISER, 4.0, 11)
		var line_at := span.y + 0.6
		for i in 420:
			TrafficSignals.force(plan, ix, iz, axis, TrafficSignals.Light.RED, 1.0)
			await _t.get_tree().physics_frame
			if i > 120 and is_instance_valid(stopper) and stopper.ride_speed < 0.05:
				break
		var at := stopper.position.z if axis == 0 else stopper.position.x
		var data: Dictionary = {}
		for r: Dictionary in cyc.riders():
			if r.node == stopper:
				data = r
		_t._check(not data.is_empty() and at < line_at and at > line_at - 4.0 and float(data.v) < 0.3,
			"a rider stops at a red short of the stop line (%.1f m before it, %.2f m/s)" % [line_at - at, float(data.get("v", -1.0))])
		stopper.queue_free()
	# Knocked off: a ragdoll and the bike thrown.
	var parent := rider.get_parent()
	var before := parent.get_child_count()
	rider.knock(Vector3(6.0, 4.0, 0.0))
	var doll := false
	var bike := false
	for c in parent.get_children():
		if c is Ragdoll:
			doll = true
		if c is PhysicsProp:
			bike = true
	_t._check(doll and bike and rider.is_queued_for_deletion(), "a knocked rider is a ragdoll and their bike a thrown body")
	await _t.get_tree().physics_frame
	for c in parent.get_children():
		if c is Ragdoll or c is PhysicsProp:
			c.queue_free()


## Buildings, props, trash cans, by position (the parked cars are left out: a lane takes some).
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out
