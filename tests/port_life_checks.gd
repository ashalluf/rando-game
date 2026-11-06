extends RefCounted
## The container terminal at work (PortLife, PortLifeKit, PortGate) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Checks: every kit mesh builds inside its
## triangle budget; the old crane mesh is unchanged by the split (its triangle count) and the
## split pieces add up to it; the ship replay matches the ship's batch; a crane's dual cycle is
## continuous, closed (the trolley never jumps, the spreader never goes through the ship's deck
## cargo, the boxes are where the cycle says at every lock), its tractor stands under the spreader
## while the spreader works its chassis and its loop stays in the port; the gantry's shuffle puts
## the box back; the straddle loops stay in the yard and off the gate; the port's FULL chunks mark
## their cranes and gantries and the gate chunk has its trucks and no stacks; PortLife draws them.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.get("plan")
	_meshes()
	_ship()
	if plan == null or plan.macro == null:
		return
	_cycle(plan)
	_loops(plan)
	await _live(city, plan)


func _tris(m: Mesh) -> int:
	return m.surface_get_array_index_len(0) / 3


func _meshes() -> void:
	var budget := {"straddle": [PortLifeKit.straddle_mesh(), 4500], "tractor": [PortLifeKit.tractor_mesh(), 2500],
		"chassis": [PortLifeKit.chassis_mesh(), 2500], "booth": [PortLifeKit.booth_mesh(), 1200],
		"canopy": [PortLifeKit.canopy_mesh(PortGate.LANES), 1500], "portal": [PortLifeKit.portal_mesh(PortGate.LANES), 2500],
		"office": [PortLifeKit.office_mesh(), 600], "trolley": [PortKit.sts_trolley_mesh(), 1500],
		"spreader": [PortKit.sts_spreader_mesh(), 400], "rtg_frame": [PortKit.rtg_frame_mesh(), 4000],
		"rtg_trolley": [PortKit.rtg_trolley_mesh(), 400]}
	var bad := ""
	for k: String in budget:
		var m: Mesh = budget[k][0]
		var n := _tris(m)
		if n <= 0 or n > int(budget[k][1]):
			bad += " %s=%d" % [k, n]
	_t._check(bad == "", "port life: every kit mesh builds inside its budget" + bad)
	# The split leaves the posed crane as it was: frame + trolley + spreader + ropes = the old mesh.
	var whole := _tris(PortKit.sts_mesh(false, 40.0, 30.0))
	var frame := _tris(PortKit.sts_frame_mesh())
	var parts := frame + _tris(PortKit.sts_trolley_mesh()) - 4 * 2 * 3 + _tris(PortKit.sts_spreader_mesh()) + 4 * 4 * 2
	_t._check(frame < whole and absi(parts - whole) <= 8, "port life: the working crane's frame is the posed crane less its trolley and spreader (%d + parts = %d, posed %d)" % [frame, parts, whole])
	var rtg := _tris(PortKit.rtg_mesh())
	var rtg_parts := _tris(PortKit.rtg_frame_mesh()) + _tris(PortKit.rtg_trolley_mesh())
	_t._check(rtg_parts < rtg and rtg - rtg_parts < 120, "port life: the moving gantry's frame and trolley are the gantry less its spreader (%d of %d)" % [rtg_parts, rtg])


func _ship() -> void:
	var boxes := PortLife.ship_boxes()
	var ok := boxes.size() > 60
	var idx := 0
	for b: Dictionary in boxes:
		ok = ok and int(b.index) == idx and int(b.h) < int(b.height)
		idx += 1
	_t._check(ok, "port life: the ship's deck boxes replay in order (%d boxes)" % boxes.size())


func _crane(plan: CityPlan) -> Dictionary:
	var ship := PortLife.ship_anchor()
	var x := PortLife.bay_x(ship.x + 10.0)
	return PortLife.crane_plan(plan, Vector3(x, CityChunk.PORT_YARD_TOP, ship.y - 39.5), 3)


func _cycle(plan: CityPlan) -> void:
	var c := _crane(plan)
	var period: float = c.period
	_t._check(period > 120.0 and period < 600.0, "port life: a crane's dual cycle takes %.0f s" % period)
	var dt := 0.25
	var prev := PortLife.crane_pose(c, 0.0)
	var jump := 0.0
	var through := 0
	var stand_bad := 0
	var cargo_top := 0.0
	for b: Dictionary in PortLife.ship_boxes():
		cargo_top = maxf(cargo_top, (b.centre as Vector3).y + PortKit.H_STD * 0.5)
	var ship := PortLife.ship_anchor()
	var t := dt
	var ship_side := ship.y - PortKit.SHIP_BEAM * 0.5
	var lowest_over_ship := INF
	while t < period * 2.0:
		var p := PortLife.crane_pose(c, t)
		jump = maxf(jump, absf(float(p.trolley_z) - float(prev.trolley_z)) + absf(float(p.spreader_y) - float(prev.spreader_y)))
		# Over the ship the spreader comes down only onto its two slots' tops.
		if float(p.trolley_z) > ship_side:
			var floor_y := float(c.P.top) if absf(float(p.trolley_z) - float(c.P.centre.z)) < 1.3 else (float(c.Q.top) if absf(float(p.trolley_z) - float(c.Q.centre.z)) < 1.3 else cargo_top)
			if float(p.spreader_y) < floor_y - 0.05 - (PortKit.H_STD if (p.spreader_box as Array).size() > 0 else 0.0) * 0.0:
				through += 1
			lowest_over_ship = minf(lowest_over_ship, float(p.spreader_y))
		# While the spreader is down at the chassis a tractor stands at the stop.
		if absf(float(p.trolley_z) - float(c.lane_z)) < 0.01 and float(p.spreader_y) < float(c.yc) + 0.5:
			if float(p.tractors[0].s) > 0.01 and float(p.tractors[1].s) > 0.01:
				stand_bad += 1
		prev = p
		t += dt
	_t._check(jump < 2.0, "port life: the trolley and spreader move smoothly (largest step %.2f m in %.2f s)" % [jump, dt])
	_t._check(through == 0, "port life: the spreader never goes below a slot's top over the ship (%d samples)" % through)
	_t._check(stand_bad == 0, "port life: a tractor stands under the spreader whenever it works the chassis (%d samples off)" % stand_bad)
	# The cycle closes: the same pose a period on.
	var a := PortLife.crane_pose(c, 37.0)
	var b := PortLife.crane_pose(c, 37.0 + period)
	_t._check(absf(float(a.trolley_z) - float(b.trolley_z)) < 0.01 and absf(float(a.spreader_y) - float(b.spreader_y)) < 0.01, "port life: the crane's cycle repeats every period")
	# The two tractors never meet on the loop.
	var length: float = c.loop.length
	var closest := INF
	t = 0.0
	while t < period:
		var p := PortLife.crane_pose(c, t)
		var s0 := float(p.tractors[0].s)
		var s1 := float(p.tractors[1].s)
		var gap := fposmod(s1 - s0, length)
		closest = minf(closest, minf(gap, length - gap))
		t += 0.5
	_t._check(closest > 20.0, "port life: a crane's two tractors keep at least a rig's length apart (%.1f m)" % closest)
	var pr: Rect2 = plan.macro.port_rect.grow(30.0)
	var outside := 0
	for pt: Vector2 in (c.loop.pts as PackedVector2Array):
		if not pr.has_point(pt):
			outside += 1
	_t._check(outside == 0 and length > 300.0, "port life: the tractors' loop (%.0f m) stays in the terminal" % length)


func _loops(plan: CityPlan) -> void:
	var loops := PortLife.straddle_loops(plan)
	var pr: Rect2 = plan.macro.port_rect
	var g := PortLife.grid(plan)
	var gate_rect := plan.owned_rect(g.gate.x, g.gate.y)
	var bad := 0
	var cars := 0
	for lp: Dictionary in loops:
		cars += (lp.cars as Array).size()
		for pt: Vector2 in (lp.path.pts as PackedVector2Array):
			if not pr.has_point(pt) or gate_rect.has_point(pt):
				bad += 1
	_t._check(loops.size() > 2 and cars > 3 and bad == 0, "port life: %d straddle carriers on %d loops, all in the yard" % [cars, loops.size()])
	_t._check((g.xs as Array).size() >= 3 and (g.zs as Array).size() >= 3, "port life: the yard has aisles between its chunks (%d x %d)" % [(g.xs as Array).size(), (g.zs as Array).size()])


func _live(city: Node3D, plan: CityPlan) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var home: Vector3 = ws.to_world(player.global_position)
	var ship := PortLife.ship_anchor()
	player.global_position = ws.to_local(Vector3(ship.x, 2.0, ship.y - 60.0))
	player.set("velocity", Vector3.ZERO)
	city.update_streaming(true)
	for i in 4:
		await _tree.physics_frame
	await _tree.process_frame
	await _tree.process_frame
	var cranes := _tree.get_nodes_in_group("port_crane").size()
	var rtgs := _tree.get_nodes_in_group("port_rtg").size()
	_t._check(cranes >= 2, "port life: the quay's FULL chunks mark their working cranes (%d)" % cranes)
	var life: Node = city.get_node_or_null("PortLife")
	_t._check(life != null, "port life: the PortLife node is in the city")
	if life != null:
		for i in 40:
			await _tree.process_frame
		var layers: Dictionary = life.get("_layers")
		var drawn := 0
		for k: String in ["trolley", "spreader", "box", "tractor", "chassis"]:
			if layers.has(k) and int(layers[k].get("n")) > 0:
				drawn += 1
		_t._check(drawn == 5, "port life: trolleys, spreaders, boxes, tractors and chassis are drawn (%d kinds, %d gantries marked)" % [drawn, rtgs])
		var hidden: Dictionary = life.get("_ship_hidden")
		_t._check(_tree.get_nodes_in_group("port_ship_boxes").is_empty() or hidden.size() == cranes * 2, "port life: the ship's boxes its cranes work are taken out of its batch (%d)" % hidden.size())
	# The gate: no stacks, its trucks parked.
	var g := PortLife.grid(plan)
	var gr := plan.owned_rect(g.gate.x, g.gate.y)
	player.global_position = ws.to_local(Vector3(gr.get_center().x, 2.0, gr.get_center().y))
	city.update_streaming(true)
	for i in 30:
		await _tree.process_frame
	var trucks := 0
	for v: Node in _tree.get_nodes_in_group("vehicle"):
		if v.has_meta("port_dray") and is_instance_valid(v):
			trucks += 1
	var chunk: Node = null
	for c: Node in city.find_children("*", "", true, false):
		if c is CityChunk and (c as CityChunk).ix == g.gate.x and (c as CityChunk).iz == g.gate.y and (c as CityChunk).level == CityChunk.Level.FULL:
			chunk = c
	var stacks := -1
	if chunk:
		var nodes: Dictionary = chunk.get("_mm_nodes")
		stacks = 0 if not nodes.has("container") else (nodes.container as MultiMeshInstance3D).multimesh.instance_count
	_t._check(trucks >= 3 and stacks == 0, "port life: the gate has %d drayage trucks in its lanes and no stacks (%d boxes)" % [trucks, stacks])
	player.global_position = ws.to_local(home)
	player.set("velocity", Vector3.ZERO)
	city.update_streaming(true)
	await _tree.process_frame
