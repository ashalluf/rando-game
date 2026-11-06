extends RefCounted
## The Coral Line (LightRail, LightRailKit, LightRailSystem, LightRailTrain, RailGate, RailRider)
## for tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the
## autoloads. Checks the table resolves into a sound line (downtown on the real Flower St, the
## portal, the structure over every freeway it crosses, grade-limited, stations spaced and clear
## of the junctions), the timetable (continuous, a train dwelling at a station with its doors
## open when the clock says so, the turn-round seamless), the crossings (closed before a train,
## open between), TrafficManager's lane and stop rules, a FULL and an LOD chunk's works, the
## system posing detailed trains on the track and boxing far ones, the doors, the riders, and a
## train striking whoever stands in front of it.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.plan
	var line := LightRail.of(plan)
	_check(line != null, "the light rail resolves on the city's plan")
	if line == null:
		return
	_layout(plan, line)
	_timetable(line)
	_crossings(line)
	_traffic(city, plan, line)
	await _chunks(city, plan, line)
	await _system(city, plan, line)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _layout(plan: CityPlan, line: LightRail) -> void:
	_check(line.length > 4000.0 and line.stations.size() == LightRail.STATIONS.size(),
		"the line is %.0f m long with %d stations" % [line.length, line.stations.size()])
	var flower := DowntownReal.named(CityPlan.AXIS_X, "FLOWER ST")
	_check(absf(line.pts[0].x - float(flower[0])) < 0.01, "downtown, the line runs down the real Flower St (x %.1f)" % line.pts[0].x)
	_check(int(line.stations[0].mode) == LightRail.Mode.TUNNEL and line.mouth_s < line.daylight_s,
		"the first station is underground and the portal climbs to the street")
	var modes := {}
	for m in line.mode:
		modes[m] = true
	_check(modes.size() == 4, "the line has tunnel, trench, street and structure")
	# Grade: the structure never steeper than its limit (at grade the line is the street's);
	# never under the street past the portal.
	var steep := 0.0
	var under := 0.0
	for i in range(1, line.pts.size()):
		if line.run[i] < line.daylight_s + 2.0:
			continue
		under = maxf(under, line.street[i] - line.rail[i])
		if line.mode[i] != LightRail.Mode.AERIAL or line.mode[i - 1] != LightRail.Mode.AERIAL:
			continue
		var g := absf(line.rail[i] - line.rail[i - 1]) / maxf(line.run[i] - line.run[i - 1], 0.01)
		steep = maxf(steep, g)
	_check(steep < LightRail.MAX_GRADE + 0.012, "the structure is never steeper than %.1f %% (%.2f %%)" % [LightRail.MAX_GRADE * 100.0, steep * 100.0])
	_check(under < 0.01, "past the portal the rail is never under the street (%.3f m)" % under)
	var clear := true
	for f in line.flyovers:
		clear = clear and float(line.sample(float(f.s)).y) >= float(f.deck) + LightRail.AERIAL_CLEAR - 0.6
	_check(line.flyovers.size() >= 2 and clear, "the structure clears all %d freeway decks it crosses" % line.flyovers.size())
	# Stations: spaced like a light rail's, the at-grade ones clear of every junction.
	var gaps_ok := true
	for i in range(1, line.stations.size()):
		var gap := float(line.stations[i].s) - float(line.stations[i - 1].s)
		gaps_ok = gaps_ok and gap > 350.0 and gap < 1600.0
	_check(gaps_ok, "stations are 0.35-1.6 km apart")
	var aerial_station := false
	var junction_free := true
	for st in line.stations:
		if int(st.mode) == LightRail.Mode.AERIAL:
			aerial_station = true
		if int(st.mode) != LightRail.Mode.GRADE:
			continue
		for k in 9:
			var s: float = float(st.s) + (float(k) / 8.0 - 0.5) * (LightRail.PLATFORM_LENGTH + LightRail.RAMP_RUN * 2.0)
			junction_free = junction_free and not _in_junction(plan, line.sample(s).pos)
	_check(aerial_station, "one station stands on the structure")
	_check(junction_free, "no at-grade platform or ramp stands in a junction")
	# Level stations: the platform is flat to a few centimetres.
	var level := true
	for st in line.stations:
		var a := float(line.sample(float(st.s) - LightRail.PLATFORM_LENGTH * 0.5).y)
		var b := float(line.sample(float(st.s) + LightRail.PLATFORM_LENGTH * 0.5).y)
		if int(st.mode) == LightRail.Mode.AERIAL:
			level = level and absf(a - b) < 0.15
	_check(level, "an aerial platform is level")
	# Lots keep clear of the structure; at grade the line is inside its road.
	var p0: Vector2 = line.sample(line.flyovers[0].s).pos if not line.flyovers.is_empty() else Vector2.ZERO
	_check(line.blocks_rect(Rect2(p0 - Vector2(3, 3), Vector2(6, 6)), 1.0), "the structure keeps lots off it")
	_check(not line.cut_rects().is_empty() and line.cut_rects()[0].size.y > 100.0, "the portal's trench is cut out of the road")


func _in_junction(plan: CityPlan, p: Vector2) -> bool:
	var k := plan.block_index_at(p)
	for dx in 2:
		for dz in 2:
			var rx := plan.road_pos(CityPlan.AXIS_X, k.x + dx)
			var rz := plan.road_pos(CityPlan.AXIS_Z, k.y + dz)
			if absf(p.x - rx) < plan.road_width(CityPlan.AXIS_X, k.x + dx) * 0.5 and absf(p.y - rz) < plan.road_width(CityPlan.AXIS_Z, k.y + dz) * 0.5:
				return true
	return false


func _timetable(line: LightRail) -> void:
	_check(line.fleet >= 2 and absf(line.headway * line.fleet - (line.trip_len[0] + line.trip_len[1])) < 0.01,
		"the fleet (%d) fills the round trip at a %.0f s headway" % [line.fleet, line.headway])
	# Continuity: nobody jumps between two clocks half a second apart.
	var jump := 0.0
	for t0: float in [3600.0, 3777.7, 5123.4, 9000.0]:
		var a := line.trains_at(t0)
		var b := line.trains_at(t0 + 0.5)
		for x in a:
			for y in b:
				if int(x.id) == int(y.id) and int(x.dir) == int(y.dir):
					jump = maxf(jump, absf(float(x.s) - float(y.s)))
	_check(jump < 0.5 * (LightRail.SPEED_AERIAL + 1.0), "trains move continuously (%.2f m in 0.5 s at most)" % jump)
	# The turn-round: the train that arrives at a terminus is the one that leaves it.
	var tl0: float = line.trip_len[0]
	var arrive := float(line.phase[0]) + 10.0 * line.headway + tl0 - 0.01
	var before := line.trains_at(arrive)
	var after := line.trains_at(arrive + 0.02)
	var seam := false
	for x in before:
		if int(x.dir) == 1 and absf(float(x.s) - float(line.trip_s[0][line.trip_s[0].size() - 1])) < 0.5:
			for y in after:
				if int(y.dir) == -1 and int(y.id) == int(x.id) and absf(float(y.s) - (float(x.s) - LightRail.TRAIN_LENGTH)) < 0.5:
					seam = true
	_check(seam, "a train that arrives at the terminus turns round as the same car set")
	# Dwells: at a station, standing, doors open.
	var ok := true
	for i in line.stations.size():
		for d in 2:
			var t := line.clock_at_station(i, d)
			var found := false
			for x in line.trains_at(t):
				var mid := float(x.s) - float(x.dir) * LightRail.TRAIN_LENGTH * 0.5
				if absf(mid - float(line.stations[i].s)) < 2.0 and bool(x.dwell) and float(x.doors) > 0.9:
					found = true
			ok = ok and found
	_check(ok, "every station has trains dwelling at it both ways, doors open")


func _crossings(line: LightRail) -> void:
	var gates := 0
	for c in line.crossings:
		if bool(c.gates):
			gates += 1
	_check(gates >= 5, "the line crosses %d roads with gates (%d crossings)" % [gates, line.crossings.size()])
	if line.crossings.is_empty():
		return
	var k := line.crossings.size() / 2
	var c: Dictionary = line.crossings[k]
	var t := line.clock_at_crossing(k, 0, 6.0)
	_check(line.crossing_state(c, t), "a crossing is closed 6 s before a train")
	var open_found := false
	for q in 60:
		if not line.crossing_state(c, t + 60.0 + float(q) * 4.0):
			open_found = true
			break
	_check(open_found, "and open again between trains")
	# The gate's phase: closed for (GATE_LEAD - 6) s when the train is 6 s off, so the arm is down.
	var ph := line.crossing_phase(c, t)
	_check(absf(ph - (LightRail.GATE_LEAD - 6.0)) < 1.5, "6 s before a train the crossing has been closed %.1f s" % ph)
	var g := RailGate.new()
	g._pivot = Node3D.new()
	g.pose_at(ph, true)
	_check(g.lowered > 0.99, "and its gates are down")
	g.pose_at(-120.0, false)
	_check(g.lowered < 0.01, "and up long after")
	g._pivot.free()
	g.free()


func _traffic(city: Node3D, plan: CityPlan, line: LightRail) -> void:
	var tm: TrafficManager = null
	for n in city.get_children():
		if n is TrafficManager:
			tm = n
	_check(tm != null, "the city has its traffic")
	if tm == null:
		return
	var width := plan.road_width(CityPlan.AXIS_X, line.avenue_index)
	var outer := CityPlan.lane_center(width, 2, 1)
	var ok := true
	for i in 12:
		var lane := tm._lane_offset(CityPlan.AXIS_X, line.avenue_index, 1 if i % 2 == 0 else -1)
		ok = ok and absf(absf(lane) - outer) < 0.01
	_check(ok, "traffic on the line's street keeps to the outer lane, clear of the trackway")
	var half_way := outer - 1.0 - (LightRail.TRACK_HALF + LightRailKit.TRACKWAY_EXTRA)
	_check(half_way > 0.2, "the outer lane's cars clear the trackway (%.2f m)" % half_way)
	var c: Dictionary = line.crossings[0]
	var was := LightRail.closed
	LightRail.closed = {c.node: int(c.axis)}
	_check(LightRail.crossing_closed(c.node, int(c.axis)) and not LightRail.crossing_closed(c.node, 1 - int(c.axis)),
		"a closed crossing stops the road crossed, not the line's own")
	LightRail.closed = was


func _chunks(city: Node3D, plan: CityPlan, line: LightRail) -> void:
	# The chunk round the first at-grade station, FULL: track, overhead, station, riders.
	var st: Dictionary = {}
	for s in line.stations:
		if int(s.mode) == LightRail.Mode.GRADE:
			st = s
			break
	var key := plan.chunk_index_at(st.pos)
	var chunk: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	chunk.build()
	_check(chunk.has_node("RailStructure") and chunk.has_node("RailBody"), "a FULL station chunk builds the line's mesh and collision")
	var riders := 0
	for n in chunk.get_children():
		if n is RailRider:
			riders += 1
	_check(riders >= 1, "people wait on the platform (%d)" % riders)
	var kit := LightRailKit.new(chunk)
	var idx := line.indices_in(chunk.owned_rect())
	for i in idx:
		kit._segment(i)
	kit._features(chunk.owned_rect())
	var body := kit.body.commit_to_arrays()
	var verts: PackedVector3Array = body[Mesh.ARRAY_VERTEX] if body.size() > 0 and body[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	var finite := true
	for v in verts:
		finite = finite and is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
	_check(verts.size() > 3000 and finite, "the station chunk's works are real geometry (%d vertices), no NaN" % verts.size())
	var tris_per_m := float(verts.size()) / 3.0 / maxf(float(idx.size()) * LightRail.STEP, 1.0)
	_check(tris_per_m < 900.0, "a FULL chunk's line stays inside its budget (%.0f triangles a metre, stations and all)" % tris_per_m)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# A gated crossing's chunk builds its gates.
	var cr: Dictionary = {}
	for c in line.crossings:
		if bool(c.gates):
			cr = c
			break
	var ck: CityChunk = city._new_chunk(plan.chunk_index_at(cr.pos), CityChunk.Level.FULL)
	ck.build()
	var gates := 0
	for n in ck.get_children():
		if n is RailGate:
			gates += 1
	_check(gates == 2, "a level crossing has a gate at each approach (%d)" % gates)
	ck.get_parent().remove_child(ck)
	ck.free()
	# LOD: nothing of its own - the system's far line draws the line there.
	var aerial_s := 0.0
	for i in line.pts.size():
		if line.mode[i] == LightRail.Mode.AERIAL:
			aerial_s = line.run[i] + 60.0
			break
	var lod: CityChunk = city._new_chunk(plan.chunk_index_at(line.sample(aerial_s).pos), CityChunk.Level.LOD)
	lod.build()
	_check(not lod.has_node("RailStructure"), "an LOD chunk leaves the line to the far mesh")
	lod.get_parent().remove_child(lod)
	lod.free()
	await _tree.process_frame


func _system(city: Node3D, plan: CityPlan, line: LightRail) -> void:
	var sys: LightRailSystem = city.get_node_or_null("LightRail") as LightRailSystem
	_check(sys != null, "the city runs the line (LightRailSystem)")
	if sys == null:
		return
	var player := _tree.get_first_node_in_group("player") as Player
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var home: Vector3 = ws.to_world(player.global_position)
	var clock_was := LightRail.clock
	var hold_was := sys.hold
	sys.hold = true
	if not sys._ready_done:
		sys._setup()
	# At the first at-grade station, a train dwelling outbound.
	var si := 1
	for i in line.stations.size():
		if int(line.stations[i].mode) == LightRail.Mode.GRADE:
			si = i
			break
	var st: Dictionary = line.stations[si]
	var stand: Vector2 = (st.pos as Vector2) + Vector2(14.0, 0.0)
	player.global_position = ws.to_local(Vector3(stand.x, float(st.y) + 30.0, stand.y))
	player.velocity = Vector3.ZERO
	LightRail.clock = line.clock_at_station(si, 0)
	sys.step()
	_check(not sys.detailed.is_empty(), "a train at the player's station is drawn in detail")
	# The one standing at the platform (another may be passing).
	var tr: LightRailTrain = null
	for c in sys.get_children():
		if c is LightRailTrain and (c as LightRailTrain).visible and (tr == null or (c as LightRailTrain).doors_open > tr.doors_open):
			tr = c
	_check(tr != null and tr.sections.size() == LightRail.CARS * 2, "the train is two cars of two sections")
	if tr:
		var on_track := true
		for k in tr.sections.size():
			var xf := LightRailTrain.section_world(line, tr.front_s, tr.dir, k)
			var got: Vector3 = ws.to_world(tr.sections[k].global_position)
			on_track = on_track and got.distance_to(xf.origin) < 0.05
			# Across the line: the section's centre sits on its own track (a chord's middle is a few
			# centimetres inside a curve).
			var s_mid := line.nearest_s(Vector2(got.x, got.z))
			var smp := line.sample(s_mid)
			var dd: Vector2 = smp.dir
			var rr := Vector2(-dd.y, dd.x)
			var lateral := (Vector2(got.x, got.z) - (smp.pos as Vector2)).dot(rr)
			on_track = on_track and absf(lateral - float(tr.dir) * float(smp.half)) < 0.6 and absf(got.y - float(smp.y)) < 0.6
		_check(on_track, "every section stands on its track")
		_check(tr.doors_open > 0.9 and tr.door_points().size() >= 4, "its platform-side doors are open (%d doorways)" % tr.door_points().size())
		# Doors open on the platform side: the doorways are nearer the line's centre than the train is.
		var centre_side := true
		for d in tr.door_points():
			var s_d := line.nearest_s(d)
			var c2: Vector2 = line.sample(s_d).pos
			var t2 := line.track_point(s_d, tr.dir)
			centre_side = centre_side and d.distance_to(c2) < Vector2(t2.x, t2.z).distance_to(c2)
		_check(centre_side, "the doors open onto the island platform")
	_check(sys._far_line != null and sys._far_line.mesh != null, "the line past the FULL chunks is one far mesh")
	# Far trains: boxes for the rest.
	_check(sys._far.multimesh.visible_instance_count > 0, "the trains out of detail range are boxes (%d sections)" % sys._far.multimesh.visible_instance_count)
	# Strike: the player on the track in front of a moving train.
	var moving: Dictionary = {}
	for x in line.trains_at(LightRail.clock + 40.0):
		var m := line.sample(float(x.s))
		if float(x.v) > 6.0 and int(m.mode) != LightRail.Mode.TUNNEL:
			moving = x
			break
	if not moving.is_empty():
		LightRail.clock += 40.0
		var nose := LightRailTrain.section_world(line, float(moving.s), int(moving.dir), 0)
		var fwd := -nose.basis.z.normalized()
		var spot := nose.origin + fwd * (LightRailTrain.SECTION_HALF + 0.6) + Vector3.UP * 0.9
		player.global_position = ws.to_local(spot)
		player.velocity = Vector3.ZERO
		sys._struck_at = -10.0
		sys.step()
		_check(player.velocity.length() > 5.0, "a moving train knocks the player flying (%.1f m/s)" % player.velocity.length())
	# The gates: a crossing about to see a train is closed for the traffic.
	var gk := -1
	for i in line.crossings.size():
		if bool(line.crossings[i].gates):
			gk = i
			break
	var c: Dictionary = line.crossings[gk]
	player.global_position = ws.to_local(Vector3(c.pos.x, float(line.sample(float(c.s)).y) + 30.0, c.pos.y))
	LightRail.clock = line.clock_at_crossing(gk, 0, 6.0)
	sys.step()
	_check(LightRail.crossing_closed(c.node, int(c.axis)), "the system closes a crossing a train is coming to")
	LightRail.clock = clock_was
	sys.hold = hold_was
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _tree.physics_frame
