extends RefCounted
## The Los Angeles River (LaRiver, RiverBuild, RiverBridges), for tests/smoke_test.gd. Loaded at
## run time, not named there, so it compiles after the autoloads.
##
## The route: it runs south all the way, east of Vignes past downtown, its bed falling and never
## under the city's ground plane, its corridor flat at the channel's top (the relief folds the land
## level in). Geography: the 101, the 10 and the 105 cross it on decks that clear it; the 110 never
## does; the real bridged streets bridge it. The grid: every street segment the channel crosses is
## closed or a bridge, no lot stands in the corridor, the blocks it reaches build the river (and no
## lots), no walker plans a crossing onto one. The hashes the shader shares with the script are the
## same arithmetic. A FULL chunk that owns a bridge builds the channel, water, ground and one
## collision body; LOD builds no props, the far city's capture records boxes and no nodes. Then the
## drive: a car dropped on the bed stands on it, and a car started down a ramp ends up on the bed.

var _t: Node
var _tree: SceneTree
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_ws = _tree.root.get_node("/root/WorldState")
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	var rv: LaRiver = macro.river if macro else null
	_t._check(rv != null and rv.length > 7000.0, "the Los Angeles River is built (%.0f m)" % [rv.length if rv else 0.0])
	if rv == null:
		return
	_route(rv, macro)
	_geography(rv, macro, plan)
	_grid(rv, plan)
	_hashes()
	_chunks(city, plan, rv)
	await _drive(city, plan, rv)


func _route(rv: LaRiver, macro: MacroMap) -> void:
	var south := true
	var falls := true
	var low := INF
	for i in range(1, rv.pts.size()):
		south = south and rv.pts[i].y > rv.pts[i - 1].y
		var a := rv.toe_at(rv.run[i - 1])
		var b := rv.toe_at(rv.run[i])
		falls = falls and b <= a + 0.01
		low = minf(low, rv.toe_at(rv.run[i]) - LaRiver.BED_FALL - LaRiver.LF_DEPTH)
	_t._check(south and falls and low > 0.1, "the river runs south all the way, its bed only falls, and its lowest point stays over the ground plane (%.2f m)" % low)
	var vignes := DowntownReal.GAME_ANCHOR.x + 1117.0
	var east := true
	for i in rv.pts.size():
		var p := rv.pts[i]
		if p.y > -1800.0 and p.y < 2000.0:
			east = east and p.x - rv.corridor_half(rv.run[i]) > vignes + 100.0
	_t._check(east, "past downtown the river's corridor stays east of Vignes St (the Arts District between them)")
	var flat := 0.0
	for k in 40:
		var s := rv.length * (0.05 + 0.9 * float(k) / 40.0)
		for o: float in [-rv.top_half(s) - 3.0, 0.0, rv.top_half(s) + 4.0]:
			flat = maxf(flat, absf(macro.relief_at(rv.point(s, o)) - rv.top_at(s)))
	_t._check(flat < 0.15, "the corridor's ground is the channel's top level (worst %.2f m off)" % flat)
	var mouth: Vector2 = rv.pts[rv.pts.size() - 1]
	_t._check(mouth.y > macro.bay_z - macro.bay_beach_depth - 30.0 and mouth.x > macro.port_rect.end.x and mouth.x < macro.bay_east_x,
		"the river reaches the sea on the bay's north shore east of the port (Long Beach) at %s" % mouth)


func _geography(rv: LaRiver, macro: MacroMap, plan: CityPlan) -> void:
	var crosses := {}
	for r: Dictionary in macro.freeway.routes:
		var pts: PackedVector2Array = r.points
		var hs: PackedFloat32Array = r.heights
		for i in pts.size():
			var f := rv.channel_floor(pts[i])
			if f < INF:
				var key := str(r.name).split(" ")[0]
				crosses[key] = minf(float(crosses.get(key, INF)), hs[i] - rv.top_at(rv.nearest(pts[i], 200.0).x))
	var ok := crosses.has("101") and crosses.has("10") and crosses.has("105") and not crosses.has("110")
	var clear := true
	for k: String in crosses:
		clear = clear and float(crosses[k]) > 7.0
	_t._check(ok and clear, "the 101, the 10 and the 105 cross the river on decks clear of its banks, the 110 never does (%s)" % [crosses])
	var names := {}
	var kinds := {}
	for br: Dictionary in rv.bridges(plan):
		names[br.name] = true
		kinds[int(br.kind)] = int(kinds.get(int(br.kind), 0)) + 1
	var real := true
	for n: String in ["CESAR CHAVEZ AVE", "1ST ST", "4TH ST", "6TH ST", "7TH ST", "OLYMPIC BLVD"]:
		real = real and names.has(n)
	_t._check(real and kinds.has(LaRiver.Bridge.ARCH) and kinds.has(LaRiver.Bridge.RIBBON) and kinds.has(LaRiver.Bridge.GIRDER),
		"the real bridged streets bridge it - Cesar Chavez, 1st, 4th, 6th, 7th, Olympic - in arch, ribbon and girder designs (%d bridges)" % rv.bridges(plan).size())
	_t._check(not rv.rail_bridge(plan).is_empty() and rv.ramps(plan).size() >= 8,
		"a freight rail bridge and %d access ramps into the channel" % rv.ramps(plan).size())


## Every road segment the channel's opening reaches is closed or a bridge; no lot near the river
## stands in the corridor; a river block has no lots and no crossing walkers.
func _grid(rv: LaRiver, plan: CityPlan) -> void:
	var leaks := ""
	var lots_in := 0
	var river_blocks := 0
	var lot_blocks := 0
	var lo := plan.block_index_at(Vector2(rv.bounds.position.x + 120.0, rv.bounds.position.y + 120.0))
	var hi := plan.block_index_at(Vector2(rv.bounds.end.x - 120.0, rv.bounds.end.y - 120.0))
	for ix in range(lo.x, hi.x + 1):
		for iz in range(lo.y, hi.y + 1, 2):
			var rect := plan.owned_rect(ix, iz)
			for axis in 2:
				var k := ix + 1 if axis == CityPlan.AXIS_X else iz + 1
				var c := plan.road_pos(axis, k)
				var w := plan.road_width(axis, k)
				var b: Rect2 = plan.block(ix, iz).rect
				var along := b.get_center()[1 - axis]
				var r := Rect2(c - w * 0.5, b.position.y, w, b.size.y) if axis == CityPlan.AXIS_X else Rect2(b.position.x, c - w * 0.5, b.size.x, w)
				# The opening, less the bank roads: what a car on the road would drop into.
				var into := false
				for m in 9:
					var q: Vector2 = r.position + r.size * (Vector2(0.5, float(m) / 8.0) if axis == CityPlan.AXIS_X else Vector2(float(m) / 8.0, 0.5))
					var nr := rv.nearest(q, 60.0)
					if nr.w > 0.5 and nr.x > 1.0 and nr.x < rv.length - 1.0 and absf(nr.y) < rv.top_half(nr.x):
						into = true
				if into and plan.road_open(axis, k, along) and rv.segment(plan, axis, k, plan._index_at(1 - axis, along)) != LaRiver.Seg.BRIDGE:
					leaks += " %s" % [Vector3i(axis, k, ix if axis == CityPlan.AXIS_Z else iz)]
			if plan.river_block(ix, iz):
				river_blocks += 1
				if not plan.lots(ix, iz).is_empty():
					lots_in += 1
			else:
				for lot: Dictionary in plan.lots(ix, iz):
					lot_blocks += 1
					var size: Vector2 = lot.size
					var lr := Rect2((lot.center as Vector2) - size * 0.5, size)
					for m in 5:
						var corners: Array[Vector2] = [lr.position, lr.end, Vector2(lr.position.x, lr.end.y), Vector2(lr.end.x, lr.position.y), lr.get_center()]
						var q: Vector2 = corners[m]
						if rv.in_corridor(q):
							lots_in += 1
	_t._check(leaks == "" and river_blocks > 20 and lots_in == 0 and lot_blocks > 50,
		"no open street drops into the channel unless it is a bridge, no lot in the corridor (%d river blocks, %d lots checked; leaks:%s)" % [river_blocks, lot_blocks, leaks])


## The outfalls' slots: LaRiver.ihash() is the shader's ihash() (lowbias32), and the shader carries
## the same constants.
func _hashes() -> void:
	# lowbias32 (Wellons) of 1 and 7919, worked out in Python's arbitrary-precision integers.
	var ok := LaRiver.ihash(0) == 0 and LaRiver.ihash(1) == 0x688990c0 and LaRiver.ihash(7919) == 0x8c8d506d
	var src := FileAccess.get_file_as_string("res://shaders/river_concrete.gdshader")
	ok = ok and src.contains("0x7feb352du") and src.contains("0x846ca68bu") and src.contains("7919u") and src.contains("x ^= x >> 15u")
	var mat := RiverBuild.concrete_material()
	ok = ok and is_equal_approx(float(mat.get_shader_parameter("outfall_pitch")), LaRiver.OUTFALL_PITCH) \
		and is_equal_approx(float(mat.get_shader_parameter("outfall_odds")), LaRiver.OUTFALL_ODDS)
	_t._check(ok, "the outfalls' slots hash the same in the script and the concrete shader (ihash(1) = %x)" % LaRiver.ihash(1))


func _chunks(city: Node3D, plan: CityPlan, rv: LaRiver) -> void:
	var k := Vector2i(9999, 9999)
	for br: Dictionary in rv.bridges(plan):
		if br.name == "1ST ST":
			k = br.owner
	if k == Vector2i(9999, 9999):
		return
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var concrete := chunk.get_node_or_null("RiverConcrete") as MeshInstance3D
	var water := chunk.get_node_or_null("RiverWater") as MeshInstance3D
	var ground := chunk.get_node_or_null("RiverGround") as MeshInstance3D
	var body := chunk.get_node_or_null("RiverBody") as StaticBody3D
	var buildings := 0
	var lights := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
		if c is OmniLight3D and c.is_in_group("lamp_light"):
			lights += 1
	_t._check(concrete != null and concrete.material_override == RiverBuild.concrete_material() and water != null
		and water.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and ground != null
		and ground.material_override == Industrial.ground_material() and body != null and body.collision_layer == 1
		and body.collision_mask == 0 and buildings == 0 and lights >= 2,
		"the 1st St bridge's chunk %s: concrete, water and ground meshes, one collision body, no buildings, lit lamps (%d)" % [k, lights])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var lod: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lod.build()
	var lod_ok := lod.get_node_or_null("RiverConcrete") != null and lod.get_node_or_null("ReliefFloor") == null
	for c in lod.get_children():
		if c is OmniLight3D:
			lod_ok = false
	lod.get_parent().remove_child(lod)
	lod.free()
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.capturing = true
	cap.style = city.chunk_style()
	cap.build()
	var boxes: int = (cap.captured.boxes as Array).size()
	var nodes := cap.get_child_count()
	cap.free()
	_t._check(lod_ok and boxes > 20 and nodes == 0, "LOD builds the channel without lights or a relief floor; the far city captures it as %d boxes and no nodes" % boxes)


## A car dropped on the bed stands on it; a car started down a ramp ends up on the bed.
func _drive(city: Node3D, plan: CityPlan, rv: LaRiver) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if player.has_method("is_driving") and player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	var ramp: Dictionary = rv.ramps(plan)[1]
	var s0: float = ramp.s0
	var s1: float = ramp.s1
	var sg: float = ramp.side
	var mid := rv.point((s0 + s1) * 0.5, 0.0)
	player.global_position = _ws.to_local(Vector3(mid.x, rv.top_at(s0) + 40.0, mid.y))
	player.set("velocity", Vector3.ZERO)
	city.update_streaming(true)
	# On the bed, off the low-flow channel.
	var bed_s := (s0 + s1) * 0.5
	var bed_p := rv.point(bed_s, -sg * 12.0)
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.5, 0.1, 0.1), Vehicle.Addon.NONE)
	city.add_child(car)
	car.global_position = _ws.to_local(Vector3(bed_p.x, rv.surface(bed_s, -sg * 12.0) + 1.4, bed_p.y))
	await _ticks(90)
	var y: float = _ws.to_world(car.global_position).y
	var want := rv.surface(bed_s, -sg * 12.0)
	_t._check(y > want - 0.2 and y < want + 1.4, "a car dropped in the channel stands on its bed (%.2f m over it)" % (y - want))
	# Down the ramp: at its head, facing down it, rolling at 7 m/s with the throttle off.
	var w := LaRiver.RAMP_WIDTH
	var head_o := sg * (rv.top_half(s0) - w * 0.5)
	var head := rv.point(s0 + signf(s1 - s0) * 2.0, head_o)
	var down: Vector2 = rv.at(s0)[1] * signf(s1 - s0)
	car.global_position = _ws.to_local(Vector3(head.x, rv.top_at(s0) + 1.2, head.y))
	car.global_basis = Basis(Vector3.UP, atan2(-down.x, -down.y))
	car.linear_velocity = Vector3(down.x, -0.6, down.y) * 7.0
	car.angular_velocity = Vector3.ZERO
	if car.has_method("hold_crash_watch"):
		car.hold_crash_watch()
	var lowest := INF
	for i in 30:
		await _ticks(10)
		var wp: Vector3 = _ws.to_world(car.global_position)
		lowest = minf(lowest, wp.y)
	var end: Vector3 = _ws.to_world(car.global_position)
	var nr := rv.nearest(Vector2(end.x, end.z), 80.0)
	var bed_y := rv.surface(nr.x, nr.y)
	_t._check(nr.w > 0.5 and absf(nr.y) < rv.bed_half(nr.x) + 2.0 and end.y < rv.top_at(nr.x) - 3.0 and lowest > bed_y - 0.6,
		"a car rolled down an access ramp ends on the channel's bed (%.1f m over it, %.1f m from the centre line)" % [end.y - bed_y, absf(nr.y)])
	car.queue_free()
	player.global_position = _ws.to_local(home)
	player.set("velocity", Vector3.ZERO)
	await _ticks(3)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
