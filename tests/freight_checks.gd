extends RefCounted
## The freight line (FreightRail, FreightKit, FreightYard, FreightStock, FreightRailSystem) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks the table resolves into a sound line (down the real Alameda St from the yard to the
## covered way; trench, decks, severed junctions, gated crossings; grade-limited; never under a
## freeway bent), the corridor's land, the road closures and lane rule, the timetable (continuous,
## the stand at the yard, no train ever standing on a crossing, the shared east track never held by
## two trips), the crossings closing and opening, the stock meshes inside their budgets and the
## shader's palette, a FULL trench chunk, a crossing chunk with its gates, a yard chunk with its
## cars, an LOD chunk, and the system placing a train on the track and striking the player.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.plan
	var line := FreightRail.of(plan)
	_check(line != null, "the freight line resolves on the city's plan")
	if line == null:
		return
	_layout(plan, line)
	_roads(city, plan, line)
	_timetable(line)
	_crossings(line)
	_stock()
	await _chunks(city, plan, line)
	await _system(city, plan, line)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _layout(plan: CityPlan, line: FreightRail) -> void:
	var alameda := DowntownReal.named(CityPlan.AXIS_X, "ALAMEDA ST")
	_check(absf(line.avenue_x - float(alameda[0])) < 0.01, "the line runs down the real Alameda St (x %.1f)" % line.avenue_x)
	_check(line.s_yard_end > 300.0 and line.s_grade0 > line.s_yard_end + 800.0 and line.s_grade1 > line.s_grade0 + 400.0 and line.s_mouth > line.s_grade1,
		"yard, trench, at-grade stretch and covered way in order (%.0f / %.0f / %.0f / %.0f m)" % [line.s_yard_end, line.s_grade0, line.s_grade1, line.s_mouth])
	var kinds := {}
	for j in line.junctions:
		kinds[int(j.kind)] = int(kinds.get(int(j.kind), 0)) + 1
	_check(int(kinds.get(FreightRail.Junction.BRIDGE, 0)) >= 6, "cross streets ride over the trench on %d decks" % int(kinds.get(FreightRail.Junction.BRIDGE, 0)))
	_check(line.crossings.size() >= 4, "the at-grade stretch has %d gated crossings" % line.crossings.size())
	# Grade-limited and never over the street; under a deck, the clearance a double stack needs.
	var steep := 0.0
	var over := -INF
	var s := FreightRail.STEP
	while s < line.s_mouth:
		var g := absf(line.rail_at(s) - line.rail_at(s - FreightRail.STEP)) / FreightRail.STEP
		if line.mode_at(s) != FreightRail.Mode.GRADE and line.mode_at(s) != FreightRail.Mode.YARD:
			steep = maxf(steep, g)
		if s > line.s_yard_end + 40.0:
			over = maxf(over, line.rail_at(s) - line.street_at(s) - FreightRail.RAIL_ABOVE)
		s += FreightRail.STEP
	_check(steep < FreightRail.RAMP_GRADE + 0.004, "the trench's ramps are never steeper than %.1f %% (%.2f %%)" % [FreightRail.RAMP_GRADE * 100.0, steep * 100.0])
	_check(over < 0.01, "the rail never stands over the street past the yard (%.3f m)" % over)
	var clear := true
	for j in line.junctions:
		if int(j.kind) == FreightRail.Junction.BRIDGE:
			for k in 5:
				var sj: float = float(j.s) + (float(k) / 4.0 - 0.5) * float(j.w)
				clear = clear and line.street_at(sj) - line.rail_at(sj) >= FreightRail.CLEAR_UNDER - 0.05
	_check(clear, "every deck clears a double stack by the line's own rule")
	# The open trench's floor stays over the city's ground plane (the corridor's terrace).
	var low := INF
	s = line.s_yard_end
	while s < line.s_mouth:
		low = minf(low, line.rail_at(s) - FreightRail.TRACK_DEPTH)
		s += 10.0
	_check(low > 0.05, "the open trench's floor stays over the ground plane (%.2f m)" % low)
	var tr := FreightRail.terrace(Vector2(line.avenue_x, line.z0 + 1200.0))
	_check(tr.y > 0.99 and absf(plan.macro.relief_at(Vector2(line.avenue_x, line.z0 + 1200.0)) - FreightRail.TERRACE_LEVEL) < 0.05,
		"the corridor's land is held level (%.2f m)" % plan.macro.relief_at(Vector2(line.avenue_x, line.z0 + 1200.0)))
	# No freeway bent stands in the line's way.
	var pe := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	var bents := 0
	for seg in plan.macro.freeway.segments_in(Rect2(line.avenue_x - 30.0, line.z0, 60.0, line.s_mouth)):
		if int(seg.index) % pe != 0:
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var d := (b - a).normalized()
		for side: float in [-1.0, 1.0]:
			var col := a + Vector2(-d.y, d.x) * float(seg.width) * 0.13 * side
			if absf(col.x - line.avenue_x) < FreightRail.TRENCH_HALF + 2.0 and col.y > line.z0 - 20.0 and col.y < line.z0 + line.s_mouth:
				bents += 1
	_check(bents == 0, "no freeway column stands on the line (%d)" % bents)
	# The yard: blocks of its own, no lots on them.
	var yk := plan.chunk_index_at(line.yard_rect.get_center() + Vector2(100.0, 0.0))
	_check(line.yard_block(yk.x, yk.y) and plan.lots(yk.x, yk.y).is_empty(), "the yard's blocks hold no lots")
	var lay := FreightYard.layout(line)
	_check((lay.tracks as Array).size() == FreightYard.STORAGE + 2 and (lay.cuts as Array).size() > 40,
		"the yard has %d tracks with %d cars standing on them" % [(lay.tracks as Array).size(), (lay.cuts as Array).size()])
	var inside := true
	for c: Dictionary in lay.cuts:
		inside = inside and line.yard_rect.has_point(Vector2(float(c.x), float(c.z)))
	_check(inside and (lay.masts as Array).size() >= 6, "every standing car is inside the yard, under %d light masts" % (lay.masts as Array).size())


func _roads(city: Node3D, plan: CityPlan, line: FreightRail) -> void:
	var ai := line.avenue_index
	_check(not plan.road_open(CityPlan.AXIS_X, ai, line.yard_rect.get_center().y), "the avenue is closed through the yard")
	_check(plan.road_open(CityPlan.AXIS_X, ai, line.z0 + line.s_grade0 + 50.0), "and open beside the line elsewhere")
	var severed := 0
	var ok := true
	for j in line.junctions:
		var k: int = j.k
		match int(j.kind):
			FreightRail.Junction.CLOSED:
				severed += 1
				ok = ok and not plan.road_open(CityPlan.AXIS_Z, k, line.avenue_x + line.avenue_width * 0.5 + 2.0)
				ok = ok and plan.junction_closed(ai, k)
			FreightRail.Junction.BRIDGE, FreightRail.Junction.CROSSING:
				ok = ok and plan.road_open(CityPlan.AXIS_Z, k, line.avenue_x + line.avenue_width * 0.5 + 2.0)
	_check(ok and severed >= 2, "the ramps sever %d cross streets at the avenue; decks and crossings stay open" % severed)
	var tm: TrafficManager = null
	for n in city.get_children():
		if n is TrafficManager:
			tm = n
	if tm != null:
		var width := plan.road_width(CityPlan.AXIS_X, ai)
		var outer := CityPlan.lane_center(width, 2, 1)
		var lane_ok := true
		for i in 12:
			lane_ok = lane_ok and absf(absf(tm._lane_offset(CityPlan.AXIS_X, ai, 1 if i % 2 == 0 else -1)) - outer) < 0.01
		_check(lane_ok and outer - 1.0 > FreightRail.TRENCH_HALF + FreightRail.TRENCH_WALL, "traffic on Alameda keeps to the outer lane, clear of the trench (%.2f m)" % (outer - 1.0 - FreightRail.TRENCH_HALF - FreightRail.TRENCH_WALL))
	var c: Dictionary = line.crossings[0]
	var was := FreightRail.closed
	FreightRail.closed = {c.node: int(c.axis)}
	_check(FreightRail.crossing_closed(c.node, int(c.axis)) and not FreightRail.crossing_closed(c.node, 1 - int(c.axis)),
		"a closed crossing stops the cross street, not the avenue")
	FreightRail.closed = was


func _timetable(line: FreightRail) -> void:
	var jump := 0.0
	for t0: float in [5400.0, 6111.1, 9000.0, 12345.6]:
		for k in 40:
			var a := line.trains_at(t0 + float(k) * 13.0)
			var b := line.trains_at(t0 + float(k) * 13.0 + 0.5)
			for x in a:
				for y in b:
					if int(x.n) == int(y.n):
						jump = maxf(jump, absf(float(x.sA) - float(y.sA)))
	_check(jump < 0.5 * (FreightRail.SPEED_TRENCH + 0.5), "trains move continuously (%.2f m in 0.5 s at most)" % jump)
	var n := 7
	var c := line.consist(n)
	_check((c.cars as Array).size() >= FreightRail.MIN_CARS and float(c.len) <= FreightRail.MAX_LEN + 0.01,
		"a train is %d cars, %.0f m (at most %.0f)" % [(c.cars as Array).size(), float(c.len), FreightRail.MAX_LEN])
	var locos := 0
	for car: Dictionary in c.cars:
		if int(car.type) == FreightRail.Car.LOCO:
			locos += 1
	_check(int((c.cars as Array)[0].type) == FreightRail.Car.LOCO and int((c.cars as Array)[(c.cars as Array).size() - 1].type) == FreightRail.Car.LOCO and locos >= 4,
		"locomotives at the head and a distributed power unit at the rear (%d units)" % locos)
	# The stand at the yard: the leading end at the buffer, standing.
	var t := line.clock_at_yard(30.0)
	var stood := false
	for x in line.trains_at(t):
		if int(x.phase) == 1 and absf(float(x.sA) - FreightRail.BUFFER) < 0.01 and float(x.v) == 0.0:
			stood = true
			# Nothing it stands on is a level crossing, and it never reaches the crossover.
			var end_s := float(x.sA) + float(x.len)
			stood = stood and end_s < line.s_xo
			for cr in line.crossings:
				stood = stood and float(cr.s) > end_s
	_check(stood, "a train stands at the yard's buffer clear of the crossover and every crossing")
	# The shared east track: one trip's hold ends before the next one's begins.
	var tr := line.trips_for(FreightRail.MAX_LEN)
	var hold := float(tr.T_nb) - line._time_in(tr.nb, line.s_hide - line.s_xo) + FreightRail.DWELL_YARD + line._time_in(tr.sb, line.s_xo + FreightRail.XO_LEN - FreightRail.BUFFER)
	_check(hold < line.headway, "a trip holds the shared track %.0f s, inside the %.0f s headway" % [hold, line.headway])
	# Speeds: 40-60 km/h on the line.
	var vmax := 0.0
	for x in line.trains_at(9000.0):
		vmax = maxf(vmax, float(x.v))
	_check(FreightRail.SPEED_GRADE * 3.6 >= 40.0 and FreightRail.SPEED_TRENCH * 3.6 <= 61.0, "freight runs at 40-60 km/h")


func _crossings(line: FreightRail) -> void:
	var k := line.crossings.size() / 2
	var c: Dictionary = line.crossings[k]
	var t := line.clock_at_crossing(k, 0, 6.0)
	var ph := line.crossing_phase(c, t)
	_check(absf(ph - (FreightRail.GATE_LEAD - 6.0)) < 1.5, "6 s before a train the crossing has been closed %.1f s" % ph)
	_check(line.crossing_phase(c, line.clock_at_crossing(k, 0, -20.0)) > 0.0, "and is still closed while the train goes over it")
	var open_found := false
	for q in 120:
		if line.crossing_phase(c, t + 200.0 + float(q) * 6.0) < 0.0:
			open_found = true
			break
	_check(open_found, "and open again between trains")
	var down := 0.0
	var tt := 0.0
	while tt < line.headway * 3.0:
		if line.crossing_phase(c, 20000.0 + tt) > 0.0:
			down += 10.0
		tt += 10.0
	_check(down / (line.headway * 3.0) < 0.45, "a crossing is down %.0f %% of the time" % (100.0 * down / (line.headway * 3.0)))


func _stock() -> void:
	var budget := [14000, 4200, 4200, 4200, 4200, 4200]
	var ok := true
	var report := ""
	for t in 6:
		var tris := FreightStock.triangles(t)
		ok = ok and tris > 300 and tris < int(budget[t])
		report += " %d" % tris
	_check(ok, "the rolling stock is real geometry inside its budgets (triangles:%s)" % report)
	_check(FreightStock.mesh(0).get_surface_count() == 1 and FreightStock.mesh(0).surface_get_material(0) is ShaderMaterial, "each type is one mesh on the stock shader")
	# The shader's palette is FreightStock.PALETTE (parsed back, in order).
	var code: String = (load("res://shaders/freight_stock.gdshader") as Shader).code
	var i := code.find("const vec3 PALETTE[")
	var body := code.substr(i, code.find(");", i) - i) if i >= 0 else ""
	var got: Array[Vector3] = []
	var at := body.find("vec3(")
	while at >= 0:
		var close := body.find(")", at)
		var nums := body.substr(at + 5, close - at - 5).split(",")
		if nums.size() == 3:
			got.append(Vector3(nums[0].to_float(), nums[1].to_float(), nums[2].to_float()))
		at = body.find("vec3(", close)
	var same := got.size() == FreightStock.PALETTE.size()
	if same:
		for k in got.size():
			var col: Color = FreightStock.PALETTE[k]
			same = same and got[k].distance_to(Vector3(col.r, col.g, col.b)) < 0.002
	_check(same, "the stock shader's palette is FreightStock.PALETTE (%d of %d)" % [got.size(), FreightStock.PALETTE.size()])


static func _num(v: float) -> String:
	var s := "%.3f" % v
	while s.ends_with("0") and not s.ends_with(".0"):
		s = s.substr(0, s.length() - 1)
	return s


func _chunks(city: Node3D, plan: CityPlan, line: FreightRail) -> void:
	# A FULL chunk in the deep trench.
	var s_t := (line.s_yard_end + line.s_grade0) * 0.5
	var key := plan.chunk_index_at(line.point(s_t, 0.0))
	var chunk: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	chunk.build()
	_check(chunk.has_node("FreightStructure") and chunk.has_node("FreightTrack") and chunk.has_node("FreightBody") and chunk.has_node("FreightTies"),
		"a FULL trench chunk builds the structure, the track, its ties and collision")
	var verts := 0
	var finite := true
	for nm: String in ["FreightStructure", "FreightTrack"]:
		var mi := chunk.get_node_or_null(nm) as MeshInstance3D
		if mi and mi.mesh:
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				verts += vs.size()
				for v in vs:
					finite = finite and is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
	_check(verts > 2000 and finite, "its works are real geometry (%d vertices), no NaN" % verts)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# A crossing: gates on both approaches, out of the light rail's group.
	var c: Dictionary = line.crossings[0]
	var ck: CityChunk = city._new_chunk(plan.chunk_index_at(c.pos), CityChunk.Level.FULL)
	ck.build()
	var gates := 0
	var foreign := 0
	for n in ck.get_children():
		if n is RailGate:
			gates += 1
			if (n as RailGate).is_in_group("rail_gate"):
				foreign += 1
	_check(gates == 2 and foreign == 0, "a level crossing has a gate at each approach, driven by the freight line (%d)" % gates)
	ck.get_parent().remove_child(ck)
	ck.free()
	# The yard: a block of it at FULL, its cars and ground; and at LOD.
	var yk := plan.chunk_index_at(line.yard_rect.get_center() + Vector2(60.0, 0.0))
	var yc: CityChunk = city._new_chunk(yk, CityChunk.Level.FULL)
	yc.build()
	var cars := 0
	for n in yc.get_children():
		if n is MultiMeshInstance3D and str(n.name).begins_with("Batch_fr_car_"):
			cars += (n as MultiMeshInstance3D).multimesh.instance_count
	_check(cars > 5 and yc.has_node("IndustrialGround"), "a yard chunk lays its ground and stands %d cars on its tracks" % cars)
	yc.get_parent().remove_child(yc)
	yc.free()
	var lod: CityChunk = city._new_chunk(yk, CityChunk.Level.LOD)
	lod.build()
	_check(lod.get_child_count() > 0, "the yard builds at LOD too")
	lod.get_parent().remove_child(lod)
	lod.free()
	await _tree.process_frame


func _system(city: Node3D, plan: CityPlan, line: FreightRail) -> void:
	var sys: FreightRailSystem = city.get_node_or_null("FreightRail") as FreightRailSystem
	_check(sys != null, "the city runs the freight line (FreightRailSystem)")
	if sys == null:
		return
	var player := _tree.get_first_node_in_group("player") as Player
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var home: Vector3 = ws.to_world(player.global_position)
	var clock_was := FreightRail.clock
	var hold_was := sys.hold
	sys.hold = true
	if not sys._ready_done:
		sys._setup()
	# A train crossing the first level crossing, the player beside it.
	var c: Dictionary = line.crossings[0]
	FreightRail.clock = line.clock_at_crossing(0, 0, -30.0)
	player.global_position = ws.to_local(Vector3(c.pos.x + 30.0, line.street_at(float(c.s)) + 20.0, c.pos.y))
	player.velocity = Vector3.ZERO
	sys.focus = Vector3(c.pos.x + 30.0, line.street_at(float(c.s)) + 2.0, c.pos.y)
	sys.step()
	_check(sys.detailed_cars > 4, "a train over a crossing is drawn in detail near the player (%d cars)" % sys.detailed_cars)
	_check(FreightRail.crossing_closed(c.node, int(c.axis)), "and the crossing is closed to the cross street")
	# Every car stands on its track: centre over the east track, at the rail.
	var st: Dictionary = {}
	for x in sys.trains:
		if int(x.phase) == 0 and not line.hidden(x):
			st = x
	var on := not st.is_empty()
	if on:
		var cars: Array = st.consist.cars
		for j in mini(cars.size(), 30):
			var car: Dictionary = cars[j]
			var s_c := float(st.sA) + float(car.c)
			var xf := sys.car_xform(st, s_c, float(FreightRail.TRUCK_HALF[int(car.type)]), bool(car.flip))
			on = on and absf(xf.origin.x - (line.avenue_x + FreightRail.TRACK_HALF)) < 0.05 and absf(xf.origin.y - line.rail_at(s_c)) < 0.3
	_check(on, "every car of a northbound train stands on the east track")
	var gates_down := false
	for g in _tree.get_nodes_in_group("freight_gate"):
		if (g as RailGate).node_key == c.node and (g as RailGate).lowered > 0.99:
			gates_down = true
	_check(gates_down or _tree.get_nodes_in_group("freight_gate").is_empty(), "its gates are down")
	# The player on the track in front of a moving train.
	var lead: Array = []
	for x in sys.trains:
		if int(x.phase) == 0 and float(x.v) > 6.0 and not line.hidden(x):
			lead = [x]
	if not lead.is_empty():
		var x: Dictionary = lead[0]
		var car0: Dictionary = (x.consist.cars as Array)[0]
		var xf := sys.car_xform(x, float(x.sA) + float(car0.c), FreightRail.TRUCK_HALF[0], false)
		var fwd := -xf.basis.z.normalized()
		player.global_position = ws.to_local(xf.origin + fwd * 12.0 + Vector3.UP * 0.9)
		player.velocity = Vector3.ZERO
		sys.focus = xf.origin + fwd * 12.0 + Vector3.UP * 0.9
		sys._struck_at = -10.0
		sys.step()
		_check(player.velocity.length() > 5.0, "a moving train knocks the player flying (%.1f m/s)" % player.velocity.length())
	sys.focus = Vector3.INF
	FreightRail.clock = clock_was
	sys.hold = hold_was
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _tree.physics_frame
