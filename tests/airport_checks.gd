extends RefCounted
## Airport checks for tests/smoke_test.gd (Airport, AirportTerminal, AirportKit): the layout
## holds together (gates clear of the taxiway and of each other, the flyable jets clear of every
## stand, the arrival's touchdown on a painted runway), the field's lights are all there and in the
## right places, the landmarks and their far copies exist, and a FULL airport chunk builds its
## paint, fixtures, masts and the ground crews' vehicles. Loaded at run time, so it compiles after
## the autoloads.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		return
	var macro := plan.macro
	_layout(macro)
	_lights(macro)
	_landmarks(city)
	await _chunk(city, macro)


func _layout(macro: MacroMap) -> void:
	var gates := Airport.gates()
	var taxi_edge := macro.taxiway_z - macro.taxiway_width * 0.5
	var worst_tail := -INF
	var overlap := false
	for i in gates.size():
		var g: Dictionary = gates[i]
		var tail: Vector2 = (g.nose as Vector2) + (g.n as Vector2) * Airport.JET_LENGTH
		worst_tail = maxf(worst_tail, tail.y)
		if i > 0:
			var prev: Dictionary = gates[i - 1]
			overlap = overlap or (g.centre as Vector2).distance_to(prev.centre) < Airport.ENVELOPE_HALF * 2.0
	_t._check(gates.size() == Airport.GATE_COUNT and worst_tail < taxi_edge - 4.0 and not overlap,
		"the airport's %d gates park their jets clear of the taxiway (last tail z %.0f, taxiway edge %.0f) and of each other" % [gates.size(), worst_tail, taxi_edge])
	var spots_ok := true
	for spot: Array in macro.apron_spots:
		var p: Vector2 = spot[0]
		spots_ok = spots_ok and not Airport.near_gate(p, 6.0) and macro.airport_rect.has_point(p)
		for rz: float in macro.runway_zs:
			spots_ok = spots_ok and absf(p.y - rz) > macro.runway_width * 0.5 + 10.0
	# The first spot (the smoke test's jet) rolls down the taxiway the way it faces: 300 m clear of
	# every stand.
	var run_clear := true
	var s0: Vector2 = macro.apron_spots[0][0]
	var yaw0: float = macro.apron_spots[0][2] if (macro.apron_spots[0] as Array).size() > 2 else -PI * 0.5
	var run_dir := Vector2(-sin(yaw0), -cos(yaw0))
	for k in 31:
		run_clear = run_clear and not Airport.near_gate(s0 + run_dir * float(k) * 10.0, 12.0) and macro.airport_rect.has_point(s0 + run_dir * float(k) * 10.0)
	_t._check(spots_ok and run_clear, "the flyable jets wait off the stands and the runways, the first with a clear 300 m run")
	var rws := Airport.runways(macro)
	var arr: Array = rws[macro.arrival_runway]
	var air_aim := macro.airport_rect.end.x - 190.0
	_t._check(rws.size() == macro.runway_zs.size() and macro.departure_runway != macro.arrival_runway
			and air_aim > float(arr[1]) and air_aim < float(arr[2]) and float(arr[2]) > macro.airport_rect.end.x - 10.0,
		"arrivals touch down on a painted runway (27L, x %.0f..%.0f) and depart from the other" % [float(arr[1]), float(arr[2])])
	var grass_ok := true
	for g: Rect2 in Airport.grass_rects(macro):
		for rz: float in macro.runway_zs:
			grass_ok = grass_ok and not g.intersects(Rect2(-10000.0, rz - macro.runway_width * 0.5, 20000.0, macro.runway_width))
		grass_ok = grass_ok and not g.intersects(Rect2(-10000.0, taxi_edge, 20000.0, macro.taxiway_width))
		for cx: float in Airport.CONNECTOR_XS:
			grass_ok = grass_ok and not g.intersects(Rect2(cx - Airport.CONNECTOR_WIDTH * 0.5, -10000.0, Airport.CONNECTOR_WIDTH, 20000.0))
	_t._check(grass_ok and Airport.grass_rects(macro).size() >= 6, "the infield grass stays off the runways, the taxiway and the cross taxiways (%d strips)" % Airport.grass_rects(macro).size())


func _lights(macro: MacroMap) -> void:
	var mesh := Airport.lights_mesh(macro)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var n := verts.size() / 6
	var kinds := {}
	var blue := 0
	var green := 0
	var outside := 0
	var approach := 0
	var rect := macro.airport_rect.grow(3.0)
	var arr: Array = Airport.runways(macro)[macro.arrival_runway]
	for i in n:
		var v := i * 6
		var code := uv2[v].y
		if code > 99.5:
			code -= 100.0
		var kind := int(floor(code / 10.0 + 0.001))
		kinds[kind] = true
		var c := colors[v]
		if c.b > 0.8 and c.r < 0.4:
			blue += 1
		if c.g > 0.8 and c.r < 0.4:
			green += 1
		var p := verts[v]
		if p.x > float(arr[2]) + 1.0 and absf(p.z - float(arr[0])) < 30.0:
			approach += 1
		elif not rect.has_point(Vector2(p.x, p.z)):
			outside += 1
	_t._check(n > 500 and blue > 60 and green > 60 and kinds.has(Airport.K_FIELD) and kinds.has(Airport.K_RABBIT)
			and kinds.has(Airport.K_ROTATE) and kinds.has(Airport.K_PAPI) and kinds.has(Airport.K_BEACON),
		"the airfield's lights are one mesh: %d lights, %d blue taxiway edges, %d green, every kind" % [n, blue, green])
	_t._check(approach >= 75 and outside == 0, "the approach lights run out east of the arrival threshold (%d) and nothing else leaves the field (%d)" % [approach, outside])
	# The shader the lights wear has the airfield kinds (one table in two places).
	var src := FileAccess.get_file_as_string("res://shaders/aircraft_lights.gdshader")
	_t._check(src.contains("v_kind > 6.5") and src.contains("v_kind > 4.5 && v_kind < 5.5") and src.contains("v_kind > 5.5 && v_kind < 6.5"),
		"aircraft_lights.gdshader draws the airfield kinds (PAPI, rabbit, rotating beacon)")


func _landmarks(city: Node3D) -> void:
	var ids := ["terminal", "concourse_w", "concourse_e", "control_tower", "skyhook", "airport_garage", "rental_lot", "airfield_lights", "hangars"]
	var missing: Array = []
	for id: String in ids:
		if city.get_node_or_null("FarLandmark_" + id) == null:
			missing.append(id)
	_t._check(missing.is_empty(), "every airport landmark has its far copy (missing: %s)" % [missing])
	var jets := 0
	for id: String in ["concourse_w", "concourse_e"]:
		var holder := city.get_node_or_null("FarLandmark_" + id)
		if holder:
			for mm in holder.find_children("Batch_gate_jet", "MultiMeshInstance3D", true, false):
				jets += (mm as MultiMeshInstance3D).multimesh.instance_count
	var parked := 0
	for g in Airport.gates():
		parked += 0 if bool(g.empty) else 1
	# Every stand has an instance (the empty one collapsed): AirportGround swaps them as jets come
	# and go (tests/airport_life_checks.gd).
	_t._check(jets == Airport.gates().size() and parked >= 7, "the far concourses hold an airliner instance for every stand (%d of %d, %d parked)" % [jets, Airport.gates().size(), parked])
	var lights := city.get_node_or_null("FarLandmark_airfield_lights")
	var ignored := false
	if lights:
		for mi in lights.find_children("*", "MeshInstance3D", true, false):
			ignored = ignored or (mi as MeshInstance3D).has_meta("air_ignore")
	_t._check(ignored, "the field's lights are no obstacle to the air traffic's clearance")


func _chunk(city: Node3D, macro: MacroMap) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var gate: Dictionary = Airport.gates()[2]
	var c: Vector2 = gate.centre
	var was: Vector3 = player.global_position
	player.global_position = ws.call("to_local", Vector3(c.x, 3.0, c.y + 30.0))
	city.call("update_streaming", true)
	for i in 4:
		await _tree.physics_frame
	var plan: CityPlan = city.get("plan")
	var k: Vector2i = plan.block_index_at(c)
	var chunks: Dictionary = city.get("chunks")
	var chunk: Node = chunks.get(k)
	var found := {}
	if chunk:
		for n in chunk.get_children():
			found[String(n.name)] = true
	var want := ["Batch_stripe", "Batch_ap_gate_", "Batch_ap_mast", "Batch_ap_edge"]
	var missing: Array = []
	for w: String in want:
		var hit := false
		for name: String in found:
			hit = hit or name.begins_with(w)
		if not hit:
			missing.append(w)
	_t._check(chunk != null and int(chunk.get("level")) == CityChunk.Level.FULL and missing.is_empty(),
		"a FULL airport chunk paints its stands and parks the ground crews' trucks at its gate (missing: %s)" % [missing])
	var crew := 0
	for n in _tree.get_nodes_in_group("pedestrian"):
		if n is ApronCrew:
			crew += 1
	_t._check(crew >= 2, "ground crew walk round the parked jets (%d)" % crew)
	player.global_position = was
	city.call("update_streaming", true)
	await _tree.physics_frame
